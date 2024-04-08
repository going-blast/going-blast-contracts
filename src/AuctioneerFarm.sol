// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "./IAuctioneerFarm.sol";
import { PermitData } from "./IAuctioneer.sol";
import { BlastYield } from "./BlastYield.sol";

contract AuctioneerFarm is Ownable, ReentrancyGuard, IAuctioneerFarm, AuctioneerFarmEvents, BlastYield {
	using SafeERC20 for IERC20;

	PoolInfo[] public poolInfo;
	mapping(address => bool) public tokensWithPool;

	mapping(uint256 => mapping(address => UserInfo)) public userInfo;
	uint256 public totalAllocPoint;

	IERC20 public GO;
	TokenEmission public goEmission;
	IERC20 public VOUCHER;
	TokenEmission public voucherEmission;
	IERC20 public USD;
	TokenEmission public usdEmission;

	bool public initializedEmissions = false;
	uint256 public constant REWARD_PRECISION = 1e18;

	constructor(IERC20 _usd, IERC20 _go, IERC20 _voucher) Ownable(msg.sender) {
		GO = _go;
		goEmission.token = GO;
		VOUCHER = _voucher;
		voucherEmission.token = VOUCHER;
		USD = _usd;
		usdEmission.token = USD;

		_add(10000, GO);
	}

	modifier validPid(uint256 pid) {
		if (pid >= poolInfo.length) revert InvalidPid();
		_;
	}

	// BLAST

	function initializeBlast(address WETH) public onlyOwner {
		_initializeBlast(address(USD), WETH);
	}

	function claimYieldAll(
		address _recipient,
		uint256 _amountWETH,
		uint256 _amountUSDB,
		uint256 _minClaimRateBips
	) public onlyOwner {
		_claimYieldAll(_recipient, _amountWETH, _amountUSDB, _minClaimRateBips);
	}

	// ADMIN

	function initializeEmissions(uint256 _emissionAmount, uint256 _emissionDuration) public onlyOwner {
		if (initializedEmissions) revert AlreadyInitializedEmissions();
		initializedEmissions = true;

		massUpdatePools();
		_setEmission(goEmission, _emissionAmount, _emissionDuration);
	}

	function setVoucherEmissions(uint256 _emissionAmount, uint256 _emissionDuration) public onlyOwner {
		massUpdatePools();
		_setEmission(voucherEmission, _emissionAmount, _emissionDuration);
	}

	function _setEmission(TokenEmission storage tokenEmission, uint256 _amount, uint256 _duration) internal {
		tokenEmission.endTimestamp = block.timestamp + _duration;
		tokenEmission.perSecond = _amount / _duration;

		if (tokenEmission.token.balanceOf(address(this)) < _amount) revert IAuctioneerFarm.NotEnoughEmissionToken();

		emit SetEmission(address(tokenEmission.token), tokenEmission.perSecond, _duration);
	}

	function poolLength() public view returns (uint256 pools) {
		pools = poolInfo.length;
	}

	function add(uint256 allocPoint, IERC20 _token) public onlyOwner nonReentrant {
		_add(allocPoint, _token);
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
				accUsdPerShare: 0
			})
		);
		emit AddedPool(poolInfo.length - 1, allocPoint, address(_token));
	}

	function set(uint256 pid, uint256 allocPoint) public validPid(pid) onlyOwner nonReentrant {
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

	function _updateEmissions(PoolInfo storage pool) internal {
		// Todo maybe something to look at here?
		// Todo maybe add a test on that something?
		if (block.timestamp > pool.lastRewardTimestamp) {
			// GO
			if (pool.supply > 0 && totalAllocPoint > 0 && block.timestamp <= goEmission.endTimestamp) {
				uint256 secs = block.timestamp - pool.lastRewardTimestamp;
				uint256 reward = (secs * goEmission.perSecond * pool.allocPoint) / totalAllocPoint;
				pool.accGoPerShare = pool.accGoPerShare + ((reward * REWARD_PRECISION) / pool.supply);
			}

			// VOUCHER
			if (pool.supply > 0 && totalAllocPoint > 0 && block.timestamp <= voucherEmission.endTimestamp) {
				uint256 secs = block.timestamp - pool.lastRewardTimestamp;
				uint256 reward = (secs * voucherEmission.perSecond * pool.allocPoint) / totalAllocPoint;
				pool.accVoucherPerShare = pool.accVoucherPerShare + ((reward * REWARD_PRECISION) / pool.supply);
			}

			pool.lastRewardTimestamp = block.timestamp;
		}
	}

	// AUCTIONEER

	function receiveUsdDistribution(uint256 _amount) public override nonReentrant returns (bool) {
		// Nothing yet staked, reject the receive
		uint256 staked = getEqualizedTotalStaked();
		if (staked == 0) return false;

		USD.safeTransferFrom(msg.sender, address(this), _amount);

		// Distribute USD between the pools
		for (uint256 i = 0; i < poolInfo.length; ++i) {
			poolInfo[i].accUsdPerShare +=
				(_amount * poolInfo[i].allocPoint * REWARD_PRECISION) /
				(totalAllocPoint * poolInfo[i].supply);
		}

		emit ReceivedUsdDistribution(_amount);
		return true;
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

	// USER ACTIONS

	function depositWithPermit(
		uint256 pid,
		uint256 amount,
		address to,
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
	function deposit(uint256 pid, uint256 amount, address to) public nonReentrant {
		_deposit(pid, amount, to);
	}
	function _deposit(uint256 pid, uint256 amount, address to) internal validPid(pid) {
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

	function withdraw(uint256 pid, uint256 amount, address to) public validPid(pid) nonReentrant {
		PoolInfo storage pool = poolInfo[pid];
		UserInfo storage user = userInfo[pid][msg.sender];

		if (amount > user.amount) revert BadWithdrawal();

		_harvest(pool, user, to);

		user.amount -= amount;
		pool.supply -= amount;
		pool.token.safeTransfer(to, amount);

		_updateDebts(pool, user);

		emit Withdraw(msg.sender, pid, amount, to);
	}

	function _pending(
		PoolInfo storage pool,
		UserInfo storage user
	) internal view returns (PendingAmounts memory pendingAmounts) {
		pendingAmounts.go = ((user.amount * pool.accGoPerShare) / REWARD_PRECISION) - user.goDebt;
		pendingAmounts.voucher = ((user.amount * pool.accVoucherPerShare) / REWARD_PRECISION) - user.voucherDebt;
		pendingAmounts.usd = ((user.amount * pool.accUsdPerShare) / REWARD_PRECISION) - user.usdDebt;
	}

	function _harvest(PoolInfo storage pool, UserInfo storage user, address to) internal {
		_updateEmissions(pool);

		PendingAmounts memory pendingAmounts = _pending(pool, user);
		if (pendingAmounts.go > 0) GO.safeTransfer(to, pendingAmounts.go);
		if (pendingAmounts.voucher > 0) VOUCHER.safeTransfer(to, pendingAmounts.voucher);
		if (pendingAmounts.usd > 0) USD.safeTransfer(to, pendingAmounts.usd);

		if (pendingAmounts.go > 0 || pendingAmounts.voucher > 0 || pendingAmounts.usd > 0) {
			emit Harvest(msg.sender, pool.pid, pendingAmounts, to);
		}
	}

	function _updateDebts(PoolInfo storage pool, UserInfo storage user) internal {
		user.goDebt = (user.amount * pool.accGoPerShare) / REWARD_PRECISION;
		user.voucherDebt = (user.amount * pool.accVoucherPerShare) / REWARD_PRECISION;
		user.usdDebt = (user.amount * pool.accUsdPerShare) / REWARD_PRECISION;
	}

	function harvest(uint256 pid, address to) public validPid(pid) nonReentrant {
		PoolInfo storage pool = poolInfo[pid];
		UserInfo storage user = userInfo[pid][msg.sender];

		_harvest(pool, user, to);
		_updateDebts(pool, user);
	}

	function allHarvest(address to) public nonReentrant {
		for (uint256 i = 0; i < poolInfo.length; i++) {
			_harvest(poolInfo[i], userInfo[i][msg.sender], to);
			_updateDebts(poolInfo[i], userInfo[i][msg.sender]);
		}
	}

	function emergencyWithdraw(uint256 pid, address to) public validPid(pid) nonReentrant {
		PoolInfo storage pool = poolInfo[pid];
		UserInfo storage user = userInfo[pid][msg.sender];
		uint256 amount = user.amount;

		pool.supply -= amount;
		user.amount = 0;
		user.goDebt = 0;
		user.voucherDebt = 0;
		user.usdDebt = 0;

		pool.token.safeTransfer(to, amount);
		emit EmergencyWithdraw(msg.sender, pid, amount, to);
	}

	// VIEW

	function pending(uint256 pid, address _user) public returns (PendingAmounts memory pendingAmounts) {
		PoolInfo storage pool = poolInfo[pid];
		UserInfo storage user = userInfo[pid][_user];

		_updateEmissions(pool);
		pendingAmounts = _pending(pool, user);
	}
	function allPending(address _user) public returns (PendingAmounts memory pendingAmounts) {
		for (uint256 i = 0; i < poolInfo.length; i++) {
			_updateEmissions(poolInfo[i]);
			PendingAmounts memory tmpPending = _pending(poolInfo[i], userInfo[i][_user]);
			pendingAmounts.go += tmpPending.go;
			pendingAmounts.voucher += tmpPending.voucher;
			pendingAmounts.usd += tmpPending.usd;
		}
	}

	function getPool(uint256 pid) public view validPid(pid) returns (PoolInfo memory pool) {
		pool = poolInfo[pid];
	}
	function getPoolUpdated(uint256 pid) public validPid(pid) returns (PoolInfo memory pool) {
		_updateEmissions(poolInfo[pid]);
		pool = poolInfo[pid];
	}
	function getPoolUser(uint256 pid, address _user) public view validPid(pid) returns (UserInfo memory user) {
		user = userInfo[pid][_user];
	}
	function getEmission(address _token) public view returns (TokenEmission memory emission) {
		if (_token == address(GO)) emission = goEmission;
		if (_token == address(VOUCHER)) emission = voucherEmission;
		if (_token == address(USD)) emission = usdEmission;
	}
}
