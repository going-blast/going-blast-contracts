// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./IAuctioneerFarm.sol";

library TokenEmissionUtils {
	function min(uint256 a, uint256 b) internal pure returns (uint256) {
		return a <= b ? a : b;
	}
	function getEmissionsCurrent(TokenEmission storage tokenEmission, uint256 totalStaked) internal {
		if (block.timestamp <= tokenEmission.lastRewardTimestamp) return tokenEmission.rewPerShare;
		if (tokenEmission.lastRewardTimestamp >= tokenEmission.emissionFinalTimestamp) return tokenEmission.rewPerShare;

		if (totalStaked == 0) return tokenEmission.rewPerShare;

		// Take into account last emission block when calculating multiplier
		uint256 multiplier = min(block.timestamp, tokenEmission.emissionFinalTimestamp) - tokenEmission.lastRewardTimestamp;
		uint256 emission = bidPerSecond * multiplier;
		return tokenEmission.rewPerShare + ((emission * 1e18) / totalStaked);
	}

	function bringEmissionsCurrent(TokenEmission storage tokenEmission, uint256 totalStaked) internal {
		tokenEmission.rewPerShare = getEmissionsCurrent(tokenEmission, totalStaked);
		tokenEmission.lastRewardTimestamp = block.timestamp;
	}

	function setEmissions(TokenEmission storage tokenEmission, uint256 amount, uint256 duration) internal {
		tokenEmission.lastRewardTimestamp = block.timestamp;
		tokenEmission.emissionFinalTimestamp = block.timestamp + duration;
		tokenEmission.rewPerSecond = amount / duration;

		if (tokenEmission.token.balanceOf(address(this)) < amount) revert NotEnoughEmissionToken();
	}

	function getUserPending(
		TokenEmission storage tokenEmission,
		uint256 totalStaked,
		uint256 userStaked,
		uint256 userDebt
	) internal view returns (uint256) {
		return ((userStaked * getEmissionsCurrent(tokenEmission, totalStaked)) - userDebt) / REWARD_PRECISION;
	}
}

contract AuctioneerFarm is Ownable, ReentrancyGuard, IAuctioneerFarm, AuctioneerFarmEvents {
	using SafeERC20 for IERC20;
	using EnumerableSet for EnumerableSet.AddressSet;
	using TokenEmissionUtils for TokenEmission;

	bool public initializedEmissions = false;
	uint256 public constant REWARD_PRECISION = 1e18;

	// USD rewards from auctions
	IERC20 public USD;
	uint256 public usdRewardPerShare;

	// Emissions
	IERC20 public GO;
	TokenEmission public GOEmissions;
	IERC20 public BID;
	TokenEmission public BIDEmissions;

	// Staking
	EnumerableSet.AddressSet internal stakingTokens;
	mapping(address => StakingTokenData) public stakingTokenData;
	mapping(address => uint256) public userDebtGO;
	mapping(address => uint256) public userDebtBID;
	mapping(address => uint256) public userDebtUSD;

	constructor(IERC20 _usd, IERC20 _go, IERC20 _bid) Ownable(msg.sender) {
		USD = _usd;
		GO = _go;
		GOEmissions = TokenEmission({
			token: GO,
			rewPerSecond: 0,
			rewPerShare: 0,
			lastRewardTimestamp: 0,
			emissionFinalTimestamp: 0
		});
		BID = _bid;
		BIDEmissions = TokenEmission({
			token: BID,
			rewPerSecond: 0,
			rewPerShare: 0,
			lastRewardTimestamp: 0,
			emissionFinalTimestamp: 0
		});
	}

	// GO emissions are a one time thing, can't be updated
	function initializeEmissions(uint256 _emissionAmount, uint256 _emissionDuration) public onlyOwner {
		if (initializedEmissions) revert AlreadyInitializedEmissions();
		initializedEmissions = true;

		GOEmissions.setEmissions(_emissionAmount, _emissionDuration);
		emit InitializedGOEmission(GOEmissions.rewPerSecond, _emissionDuration);

		// Go Staking
		_add(GO, 10000);
	}

	function setBIDEmissions(uint256 _emissionAmount, uint256 _emissionDuration) public onlyOwner {
		GOEmissions.bringEmissionsCurrent(_getEqualizedTotalStaked());
		GOEmissions.setEmissions(_emissionAmount, _emissionDuration);
		emit UpdatedBIDEmission(BIDEmissions.rewPerSecond, _emissionDuration);
	}

	// ADMIN

	function _add(IERC20 _token, uint256 _boost) internal {
		_updateGoRewardPerShare();
		stakingTokens.add(address(_token));
		stakingTokenData[address(_token)].token = _token;
		stakingTokenData[address(_token)].boost = _boost;
		emit AddedStakingToken(address(_token), _boost);
	}

	function addLp(address _lp, uint256 _boost) public onlyOwner {
		if (stakingTokens.contains(_lp)) revert AlreadyAdded();
		if (_boost < 10000 || _boost > 30000) revert OutsideRange();
		_add(IERC20(_lp), _boost);
	}

	function removeLp(address _lp) public onlyOwner {
		_updateGoRewardPerShare();
		stakingTokenData[_lp].boost = 0;
		emit UpdatedLpBoost(_lp, 0);
	}

	function updateLpBoost(address _lp, uint256 _boost) public onlyOwner {
		if (!stakingTokens.contains(_lp)) revert NotStakingToken();
		if (_boost < 10000 || _boost > 30000) revert OutsideRange();
		_updateGoRewardPerShare();
		stakingTokenData[_lp].boost = _boost;
		emit UpdatedLpBoost(_lp, _boost);
	}

	// UTILS

	function _getEqualizedTotalStaked() internal view returns (uint256 staked) {
		staked = 0;
		for (uint256 i = 0; i < stakingTokens.values().length; i++) {
			staked += stakingTokenData[stakingTokens.at(i)].total * stakingTokenData[stakingTokens.at(i)].boost;
		}
		staked /= 10000;
	}

	function _getEqualizedUserStaked(address _user) internal view returns (uint256 userStaked) {
		userStaked = 0;
		for (uint256 i = 0; i < stakingTokens.values().length; i++) {
			userStaked +=
				stakingTokenData[stakingTokens.at(i)].userStaked[_user] *
				stakingTokenData[stakingTokens.at(i)].boost;
		}
		userStaked /= 10000;
	}

	// AUCTION INTERACTIONS

	function receiveUSDDistribution(uint256 _amount) external override returns (bool) {
		// Nothing yet staked, reject the receive
		uint256 totalStaked = _getEqualizedTotalStaked();
		if (totalStaked == 0) return false;

		USD.safeTransferFrom(msg.sender, address(this), _amount);
		usdRewardPerShare += (_amount * REWARD_PRECISION) / totalStaked;

		emit ReceivedUSDDistribution(_amount);
		return true;
	}

	function getEqualizedUserStaked(address _user) external view override returns (uint256) {
		return _getEqualizedUserStaked(_user);
	}
	function getEqualizedTotalStaked() public view returns (uint256) {
		return _getEqualizedTotalStaked();
	}
	function getStakingTokens() public view returns (address[] memory tokens) {
		tokens = stakingTokens.values();
	}
	function getStakingTokenData(address _token) public view returns (StakingTokenOnlyData memory data) {
		data.token = address(stakingTokenData[_token].token);
		data.boost = stakingTokenData[_token].boost;
		data.total = stakingTokenData[_token].total;
	}
	function getStakingTokenUserStaked(address _token, address _user) public view returns (uint256 userStaked) {
		userStaked = stakingTokenData[_token].userStaked[_user];
	}

	// CORE

	function deposit(address _token, uint256 _amount) public nonReentrant {
		if (!stakingTokens.contains(_token)) revert NotStakingToken();
		if (_amount > IERC20(_token).balanceOf(msg.sender)) revert BadDeposit();

		_harvest(msg.sender);

		if (_amount > 0) {
			IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
		}

		stakingTokenData[_token].userStaked[msg.sender] += _amount;
		stakingTokenData[_token].total += _amount;

		_updateUserDebts(msg.sender);

		emit Deposit(msg.sender, _token, _amount);
	}

	function withdraw(address _token, uint256 _amount) public nonReentrant {
		if (_amount > stakingTokenData[_token].userStaked[msg.sender]) revert BadWithdrawal();

		_harvest(msg.sender);

		if (_amount > 0) {
			stakingTokenData[_token].userStaked[msg.sender] -= _amount;
			stakingTokenData[_token].total -= _amount;
			IERC20(_token).safeTransfer(msg.sender, _amount);
		}

		_updateUserDebts(msg.sender);

		emit Withdraw(msg.sender, _token, _amount);
	}

	// HARVEST

	function _updateUserDebts(address _user) internal {
		uint256 userStaked = _getEqualizedUserStaked(_user);
		userDebtUSD[_user] = userStaked * usdRewardPerShare;
		userDebtGO[_user] = userStaked * GOEmissions.rewPerShare;
		userDebtBID[_user] = userStaked * BIDEmissions.rewPerShare;
	}

	function _pending(address _user) internal view returns (PendingAmounts memory pending) {
		uint256 userStaked = _getEqualizedUserStaked(_user);
		uint256 totalStaked = _getEqualizedTotalStaked();

		pending.usd = ((_getEqualizedUserStaked(_user) * usdRewardPerShare) - userDebtUSD[_user]) / REWARD_PRECISION;
		pending.go = GOEmissions.getUserPending(totalStaked, userStaked, userDebtGO[_user]);
		pending.bid = BIDEmissions.getUserPending(totalStaked, userStaked, userDebtBID[_user]);
	}

	function _harvest(address _user) internal {
		// Update Rewards Per Share
		GOEmissions.bringEmissionsCurrent(totalStaked);
		BIDEmissions.bringEmissionsCurrent(totalStaked);

		PendingAmounts memory pending = _pending(_user);

		if (pending.usd > 0) USD.safeTransfer(msg.sender, pending.usd);
		if (pending.go > 0) GO.safeTransfer(msg.sender, pending.go);
		if (pending.bid > 0) BID.safeTransfer(msg.sender, pending.bid);

		emit Harvested(msg.sender, pending);
	}

	function harvest() public nonReentrant {
		_harvest(msg.sender);
		_updateUserDebts(msg.sender);
	}

	function pending(address _user) public view returns (PendingAmounts memory pending) {
		return _pending(_user);
	}
}
