// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { PermitData, AlreadyLinked, NotAuctioneer, ETHTransferFailed } from "./IAuctioneer.sol";
import { BlastYield } from "./BlastYield.sol";

//         ,                ,              ,   *,    ,  , ,   *,     ,
//                               , , , ,   * * ,*     , *,,       ,      ,    .
//   .    .              .*   ,    ,,, *      , *  ,,  ,,      *
//               ,      ,   , ,  , ,       ,,** *   ,     *     ,,  ,  ,
// *           *      ,            ,,,*, * @ ,  ,,   ,     ,,
//           ,  ,       *      *  , ,,    ,@,,,,   ,, ,    , *  ,
//      , *   *   , ,           ,     **,,,@*,*,   * *,,  *       ,             ,
//       ,   ,  * ,   ,*,*  ,*  ,,  , , *  @/*/* ,, , ,   , ,     ,         ,
//       ,     *  *    *    *  , ,,,, , */*@// * ,,, , ,  ,, ,
//      *      ,,    ,, , ,  ,,    ** ,/ (*@/(*,,   ,    ,  ,   ,
//       *  *,    * , , ,, ,  , *,,..  ./*/@///,*,,* *,,      ,
//            , ,*,,* , ,  ** , ,,,,,*,//(%@&((/,/,.*.*.*  ., ., .     .
// *,    ., .,    *,,   ., ,*    .***/(%@@/@(@@/(/**.*,*,,,   .     .. ..... . .
// ,,,...    ,,   *  **  , *,,*,,**//@@*(/*@/  /@@//,,*,*,    ,,
//    *,*  *,   , ,  ,,  *  *,*,*((@@//,//*@/    (@@/*,,   ,        ,
//    , * ,* ,  ,,   ,  *, ***/*@@*/* ***/,@//* *//(*@@** ,  ,
//   ,    *   * , ,,*  *, * ,,@@*,*,,*,**,*@*/,* ,,,*//@@  ,,
//  ,,  ,,,,  , ,    *, ,,,*,,,,@@,,***,,*,@**,*,**,/@@,*, ,    ,,
// ,*    ,,, ,   ,  ,,  , , , ,,,/*@@***,, @*,,,,*@@,/,*,,,,
//    , *,,  , , **   , , ,, ,,  **,*@@,*/,@,, /@@*/** ,     ,
//   *      * *, ,,      ,,  **  * *,***@@ @*@@*/*,* ,  , ,
//         , *    ,, ,  ,    , , *,  **,**%@&,,,*, ,      ,
//          ,    *, ,,  *    , , *,,**   ,,@,,,  ,,       ,
//     *,   ,*  ,* *,  ,* , , ,, ,,*,,*,,* @,**   ,,
//    *   **     *    *   /  ,    ,, , *  ,@*, ,*, ,,     ,    ,
// *   ,, * ,,             ,  , ** ,**,, , @ *    ,
//        ,*, * ** ,*     ,,  *  ,,  *,  ,,@, ,,,*   ,
//               ,     /**,  ,   *  ,,  ,  @  ,       , ,
//        ,  /* * /     * *   *  ,*,,,  ,* @,, ,  ,        ,      ,
//   ,         ,*            ,,* *,   ,   **                        ,
//      * ,            *,  ,      ,,    ,   , ,,    ,     ,
// ,,         ,    ,      ,           ,    *
// -- ARCH --

struct PendingAmounts {
	uint256 go;
	uint256 voucher;
	uint256 eth;
}

struct TokenEmission {
	IERC20 token;
	uint256 perSecond;
	uint256 endTimestamp;
}

struct UserInfo {
	uint256 amount;
	uint256 goDebt;
	uint256 voucherDebt;
	uint256 ethDebt;
	uint256 goUnlockTimestamp;
}

struct PoolInfo {
	uint256 pid;
	IERC20 token;
	uint256 supply;
	uint256 allocPoint;
	uint256 lastRewardTimestamp;
	uint256 accGoPerShare;
	uint256 accVoucherPerShare;
	uint256 accEthPerShare;
}

interface AuctioneerFarmEvents {
	event SetEmission(address indexed _token, uint256 _perSecond, uint256 _duration);
	event AddedPool(uint256 _pid, uint256 _allocPoint, address indexed _token);
	event UpdatedPool(uint256 _pid, uint256 _allocPoint);

	event ReceivedDistribution(uint256 _amount);

	event Deposit(address indexed _user, uint256 _pid, uint256 _amount, address _to);
	event Withdraw(address indexed _user, uint256 _pid, uint256 _amount, address _to);
	event Harvest(address indexed _user, uint256 _pid, PendingAmounts _pending, address _to);
	event EmergencyWithdraw(address indexed _user, uint256 _pid, uint256 _amount, address _to);
}

interface IAuctioneerFarm {
	error BadWithdrawal();
	error BadDeposit();
	error NotEnoughEmissionToken();
	error AlreadyAdded();
	error AlreadyInitializedEmissions();
	error InvalidPid();
	error GoLocked();

	function depositLockedGo(uint256 amount, address payable user, uint256 lockDuration) external;
	function distributionReceivable() external view returns (bool);
	function receiveDistribution() external payable;
	function getEqualizedUserStaked(address _user) external view returns (uint256);
}

contract AuctioneerFarm is Ownable, ReentrancyGuard, IAuctioneerFarm, AuctioneerFarmEvents, BlastYield {
	using SafeERC20 for IERC20;

	IERC20 public GO;
	IERC20 public VOUCHER;
	address public auctioneer;
	uint256 public totalEthDistributed = 0;
	bool public initializedEmissions = false;

	PoolInfo[] public poolInfo;
	mapping(address => bool) public tokensWithPool;
	mapping(uint256 => mapping(address => UserInfo)) public userInfo;
	uint256 public totalAllocPoint;

	TokenEmission public goEmission;
	TokenEmission public voucherEmission;
	TokenEmission public ethEmission;

	uint256 public constant GO_PID = 0;
	uint256 public constant REWARD_PRECISION = 1e18;

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	constructor(address _auctioneer, IERC20 _go, IERC20 _voucher) Ownable(msg.sender) {
		auctioneer = _auctioneer;

		GO = _go;
		VOUCHER = _voucher;

		goEmission.token = GO;
		voucherEmission.token = VOUCHER;
		ethEmission.token = IERC20(address(0));

		_add(10000, GO);
	}

	function initializeEmissions(uint256 _emissionAmount, uint256 _emissionDuration) public onlyOwner {
		if (initializedEmissions) revert AlreadyInitializedEmissions();
		initializedEmissions = true;

		massUpdatePools();
		_setEmission(goEmission, _emissionAmount, _emissionDuration);
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	modifier validPid(uint256 pid) {
		if (pid >= poolInfo.length) revert InvalidPid();
		_;
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function initializeBlast() external onlyOwner {
		_initializeBlast();
	}

	function claimYieldAll(address _recipient, uint256 _minClaimRateBips) external onlyOwner {
		_claimYieldAll(_recipient, _minClaimRateBips);
	}

	function setVoucherEmissions(uint256 _emissionAmount, uint256 _emissionDuration) external onlyOwner {
		massUpdatePools();
		_setEmission(voucherEmission, _emissionAmount, _emissionDuration);
	}

	function add(uint256 allocPoint, IERC20 _token) external onlyOwner nonReentrant {
		_add(allocPoint, _token);
	}

	function set(uint256 pid, uint256 allocPoint) external validPid(pid) onlyOwner nonReentrant {
		massUpdatePools();

		totalAllocPoint = totalAllocPoint - poolInfo[pid].allocPoint + allocPoint;
		poolInfo[pid].allocPoint = allocPoint;
		emit UpdatedPool(pid, allocPoint);
	}

	function massUpdatePools() public {
		uint256 len = poolInfo.length;
		for (uint256 i = 0; i < len; ++i) {
			_updateEmissions(poolInfo[i]);
		}
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function distributionReceivable() public view returns (bool) {
		return getEqualizedTotalStaked() > 0;
	}

	function receiveDistribution() public payable nonReentrant {
		if (msg.sender != auctioneer) revert NotAuctioneer();

		if (getEqualizedTotalStaked() == 0) return;

		totalEthDistributed += msg.value;

		// Spread ETH distribution between the pools
		for (uint256 i = 0; i < poolInfo.length; ++i) {
			poolInfo[i].accEthPerShare +=
				(msg.value * poolInfo[i].allocPoint * REWARD_PRECISION) /
				(totalAllocPoint * poolInfo[i].supply);
		}

		emit ReceivedDistribution(msg.value);
	}

	function getEqualizedTotalStaked() public view returns (uint256 staked) {
		for (uint256 i = 0; i < poolInfo.length; ++i) {
			staked += poolInfo[i].allocPoint * poolInfo[i].supply;
		}
		staked /= 10000;
	}

	function getEqualizedUserStaked(address _user) public view override returns (uint256 staked) {
		for (uint256 i = 0; i < poolInfo.length; ++i) {
			staked += poolInfo[i].allocPoint * userInfo[poolInfo[i].pid][_user].amount;
		}
		staked /= 10000;
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function depositWithPermit(
		uint256 pid,
		uint256 amount,
		address payable to,
		PermitData memory _permitData
	) public nonReentrant {
		IERC20Permit(_permitData.token).permit(
			msg.sender,
			address(this),
			_permitData.value,
			_permitData.deadline,
			_permitData.v,
			_permitData.r,
			_permitData.s
		);
		_deposit(pid, amount, to);
	}

	function deposit(uint256 pid, uint256 amount, address payable to) public nonReentrant {
		_deposit(pid, amount, to);
	}

	function depositLockedGo(
		uint256 _amount,
		address payable _user,
		uint256 _depositUnlockTimestamp
	) public nonReentrant {
		if (msg.sender != auctioneer) revert NotAuctioneer();

		_deposit(GO_PID, _amount, _user);

		UserInfo storage user = userInfo[GO_PID][_user];

		if (_depositUnlockTimestamp > user.goUnlockTimestamp) {
			user.goUnlockTimestamp = _depositUnlockTimestamp;
		}
	}

	function withdraw(uint256 pid, uint256 amount, address payable to) public validPid(pid) nonReentrant {
		PoolInfo storage pool = poolInfo[pid];
		UserInfo storage user = userInfo[pid][msg.sender];

		if (amount > user.amount) revert BadWithdrawal();

		if (pid == GO_PID && block.timestamp < user.goUnlockTimestamp) revert GoLocked();

		_harvest(pool, user, to);

		user.amount -= amount;
		pool.supply -= amount;
		pool.token.safeTransfer(to, amount);

		_updateDebts(pool, user);

		emit Withdraw(msg.sender, pid, amount, to);
	}

	function harvest(uint256 pid, address payable to) public validPid(pid) nonReentrant {
		PoolInfo storage pool = poolInfo[pid];
		UserInfo storage user = userInfo[pid][msg.sender];

		_harvest(pool, user, to);
		_updateDebts(pool, user);
	}

	function allHarvest(address payable to) public nonReentrant {
		for (uint256 i = 0; i < poolInfo.length; i++) {
			_harvest(poolInfo[i], userInfo[i][msg.sender], to);
			_updateDebts(poolInfo[i], userInfo[i][msg.sender]);
		}
	}

	function emergencyWithdraw(uint256 pid, address to) public validPid(pid) nonReentrant {
		PoolInfo storage pool = poolInfo[pid];
		UserInfo storage user = userInfo[pid][msg.sender];

		if (pid == GO_PID && block.timestamp < user.goUnlockTimestamp) revert GoLocked();

		uint256 amount = user.amount;

		pool.supply -= amount;
		user.amount = 0;
		user.goDebt = 0;
		user.voucherDebt = 0;
		user.ethDebt = 0;

		pool.token.safeTransfer(to, amount);
		emit EmergencyWithdraw(msg.sender, pid, amount, to);
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function _setEmission(TokenEmission storage tokenEmission, uint256 _amount, uint256 _duration) internal {
		tokenEmission.endTimestamp = block.timestamp + _duration;
		tokenEmission.perSecond = _amount / _duration;

		if (tokenEmission.token.balanceOf(address(this)) < _amount) revert IAuctioneerFarm.NotEnoughEmissionToken();

		emit SetEmission(address(tokenEmission.token), tokenEmission.perSecond, _duration);
	}

	function _updateEmissions(PoolInfo storage pool) internal {
		(uint256 accGoPerShare, uint256 accVoucherPerShare, uint256 lastRewardTimestamp) = _getUpdatedEmissionsValues(
			pool
		);
		pool.accGoPerShare = accGoPerShare;
		pool.accVoucherPerShare = accVoucherPerShare;
		pool.lastRewardTimestamp = lastRewardTimestamp;
	}

	function _getUpdatedEmissions(PoolInfo memory pool) internal view returns (PoolInfo memory updatedPool) {
		updatedPool = pool;
		(uint256 accGoPerShare, uint256 accVoucherPerShare, uint256 lastRewardTimestamp) = _getUpdatedEmissionsValues(
			pool
		);
		updatedPool.accGoPerShare = accGoPerShare;
		updatedPool.accVoucherPerShare = accVoucherPerShare;
		updatedPool.lastRewardTimestamp = lastRewardTimestamp;
	}

	function _getUpdatedEmissionsValues(
		PoolInfo memory pool
	) internal view returns (uint256 accGoPerShare, uint256 accVoucherPerShare, uint256 lastRewardTimestamp) {
		accGoPerShare = pool.accGoPerShare;
		accVoucherPerShare = pool.accVoucherPerShare;
		lastRewardTimestamp = pool.lastRewardTimestamp;

		if (block.timestamp > pool.lastRewardTimestamp) {
			// GO
			if (pool.supply > 0 && totalAllocPoint > 0 && pool.lastRewardTimestamp <= goEmission.endTimestamp) {
				uint256 minTimestamp = block.timestamp < goEmission.endTimestamp
					? block.timestamp
					: goEmission.endTimestamp;
				uint256 secs = minTimestamp - pool.lastRewardTimestamp;
				uint256 reward = (secs * goEmission.perSecond * pool.allocPoint) / totalAllocPoint;
				accGoPerShare += ((reward * REWARD_PRECISION) / pool.supply);
			}

			// VOUCHER
			if (pool.supply > 0 && totalAllocPoint > 0 && pool.lastRewardTimestamp <= voucherEmission.endTimestamp) {
				uint256 minTimestamp = block.timestamp < voucherEmission.endTimestamp
					? block.timestamp
					: voucherEmission.endTimestamp;
				uint256 secs = minTimestamp - pool.lastRewardTimestamp;
				uint256 reward = (secs * voucherEmission.perSecond * pool.allocPoint) / totalAllocPoint;
				accVoucherPerShare += ((reward * REWARD_PRECISION) / pool.supply);
			}

			lastRewardTimestamp = block.timestamp;
		}
	}

	function _add(uint256 allocPoint, IERC20 _token) internal {
		if (tokensWithPool[address(_token)] == true) revert AlreadyAdded();
		tokensWithPool[address(_token)] = true;

		massUpdatePools();

		totalAllocPoint += allocPoint;

		poolInfo.push(
			PoolInfo({
				pid: poolInfo.length,
				token: _token,
				allocPoint: allocPoint,
				supply: 0,
				lastRewardTimestamp: block.timestamp,
				accGoPerShare: 0,
				accVoucherPerShare: 0,
				accEthPerShare: 0
			})
		);
		emit AddedPool(poolInfo.length - 1, allocPoint, address(_token));
	}

	function _deposit(uint256 pid, uint256 amount, address payable to) internal validPid(pid) {
		PoolInfo storage pool = poolInfo[pid];
		UserInfo storage user = userInfo[pid][to];

		if (amount > pool.token.balanceOf(msg.sender)) revert BadDeposit();

		if (msg.sender != to) _harvest(pool, userInfo[pid][msg.sender], to);
		_harvest(pool, user, to);

		user.amount += amount;
		pool.supply += amount;
		pool.token.safeTransferFrom(msg.sender, address(this), amount);

		if (msg.sender != to) _updateDebts(pool, userInfo[pid][msg.sender]);
		_updateDebts(pool, user);

		emit Deposit(msg.sender, pid, amount, to);
	}

	function _pending(
		PoolInfo memory pool,
		UserInfo memory user
	) internal pure returns (PendingAmounts memory pendingAmounts) {
		pendingAmounts.go = ((user.amount * pool.accGoPerShare) / REWARD_PRECISION) - user.goDebt;
		pendingAmounts.voucher = ((user.amount * pool.accVoucherPerShare) / REWARD_PRECISION) - user.voucherDebt;
		pendingAmounts.eth = ((user.amount * pool.accEthPerShare) / REWARD_PRECISION) - user.ethDebt;
	}

	function _harvest(PoolInfo storage pool, UserInfo storage user, address payable to) internal {
		_updateEmissions(pool);

		PendingAmounts memory pendingAmounts = _pending(pool, user);
		if (pendingAmounts.go > 0) GO.safeTransfer(to, pendingAmounts.go);
		if (pendingAmounts.voucher > 0) VOUCHER.safeTransfer(to, pendingAmounts.voucher);
		if (pendingAmounts.eth > 0) {
			(bool sent, ) = to.call{ value: pendingAmounts.eth }("");
			if (!sent) revert ETHTransferFailed();
		}

		if (pendingAmounts.go > 0 || pendingAmounts.voucher > 0 || pendingAmounts.eth > 0) {
			emit Harvest(msg.sender, pool.pid, pendingAmounts, to);
		}
	}

	function _updateDebts(PoolInfo storage pool, UserInfo storage user) internal {
		user.goDebt = (user.amount * pool.accGoPerShare) / REWARD_PRECISION;
		user.voucherDebt = (user.amount * pool.accVoucherPerShare) / REWARD_PRECISION;
		user.ethDebt = (user.amount * pool.accEthPerShare) / REWARD_PRECISION;
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function poolLength() public view returns (uint256 pools) {
		pools = poolInfo.length;
	}

	function pending(uint256 pid, address _user) public view returns (PendingAmounts memory pendingAmounts) {
		PoolInfo memory pool = poolInfo[pid];
		UserInfo memory user = userInfo[pid][_user];

		_getUpdatedEmissions(pool);
		pendingAmounts = _pending(pool, user);
	}
	function allPending(address _user) public view returns (PendingAmounts memory pendingAmounts) {
		for (uint256 i = 0; i < poolInfo.length; i++) {
			PoolInfo memory pool = _getUpdatedEmissions(poolInfo[i]);
			PendingAmounts memory tmpPending = _pending(pool, userInfo[i][_user]);
			pendingAmounts.go += tmpPending.go;
			pendingAmounts.voucher += tmpPending.voucher;
			pendingAmounts.eth += tmpPending.eth;
		}
	}

	function getPool(uint256 pid) public view validPid(pid) returns (PoolInfo memory pool) {
		pool = poolInfo[pid];
	}
	function getPoolUpdated(uint256 pid) public view validPid(pid) returns (PoolInfo memory pool) {
		pool = _getUpdatedEmissions(poolInfo[pid]);
	}
	function getPoolUser(uint256 pid, address _user) public view validPid(pid) returns (UserInfo memory user) {
		user = userInfo[pid][_user];
	}
	function getEmission(address _token) public view returns (TokenEmission memory emission) {
		if (_token == address(GO)) emission = goEmission;
		if (_token == address(VOUCHER)) emission = voucherEmission;
		if (_token == address(0)) emission = ethEmission;
	}

	function getAllPools()
		public
		view
		returns (PoolInfo[] memory pools, uint8[] memory decimals, string[] memory symbol)
	{
		pools = new PoolInfo[](poolInfo.length);
		decimals = new uint8[](poolInfo.length);
		symbol = new string[](poolInfo.length);
		for (uint256 i = 0; i < poolInfo.length; i++) {
			pools[i] = _getUpdatedEmissions(poolInfo[i]);
			decimals[i] = IERC20Metadata(address(poolInfo[i].token)).decimals();
			symbol[i] = IERC20Metadata(address(poolInfo[i].token)).symbol();
		}
	}

	function getAllPoolsUser(
		address _user
	) public view returns (UserInfo[] memory poolsUser, uint256[] memory balance, uint256[] memory allowance) {
		poolsUser = new UserInfo[](poolInfo.length);
		balance = new uint256[](poolInfo.length);
		allowance = new uint256[](poolInfo.length);
		for (uint256 i = 0; i < poolInfo.length; i++) {
			poolsUser[i] = userInfo[i][_user];
			balance[i] = poolInfo[i].token.balanceOf(_user);
			allowance[i] = poolInfo[i].token.allowance(_user, address(this));
		}
	}
}
