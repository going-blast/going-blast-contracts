// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./IAuctioneerFarm.sol";

struct UserDebts {
	uint256 debtGO;
	uint256 debtUSD;
}

struct StakingTokenData {
	IERC20 token;
	uint256 boost;
	uint256 total;
	mapping(address => uint256) userStaked;
}

contract AuctioneerFarm is Ownable, ReentrancyGuard, IAuctioneerFarm {
	using SafeERC20 for IERC20;
	using EnumerableSet for EnumerableSet.AddressSet;

	IERC20 public USD;
	bool public initialized = false;

	uint256 public REWARD_PRECISION = 1e18;

	// USD rewards from auctions
	uint256 public markedUSDBal;
	uint256 public usdRewardPerShare;

	// GO rewards from staking
	IERC20 public GO;
	uint256 public goPerSecond = 0;
	uint256 public goRewardPerShare;
	uint256 public goLastRewardTimestamp;
	uint256 public goEmissionFinalTimestamp;

	// Staking
	EnumerableSet.AddressSet internal stakingTokens;
	mapping(address => StakingTokenData) public stakingTokenData;
	mapping(address => uint256) public userDebtGO;
	mapping(address => uint256) public userDebtUSD;

	error DepositStillLocked();
	error BadWithdrawal();
	error BadDeposit();
	error NotStakeable();
	error OutsideRange();
	error NotEnoughGo();
	error AlreadySet();
	error AlreadyAdded();
	error AlreadyInitialized();

	event Initialized();
	event InitializedGOEmission(uint256 _goPerSecond);
	event AddedStakingToken(address indexed _token, uint256 _boost);
	event UpdatedLpBoost(address indexed _token, uint256 _boost);
	event ReceivedUSDDistribution(uint256 _amount);

	event Deposit(address indexed _user, address indexed _token, uint256 _amount);
	event Withdraw(address indexed _user, address indexed _token, uint256 _amount);
	event Harvested(address indexed _user, uint256 _usdHarvested, uint256 _goHarvested);

	constructor(address _go, uint256 _emissionAmount, uint256 _emissionDuration) Ownable(msg.sender) {
		GO = IERC20(_go);
		if (GO.balanceOf(address(this)) < _emissionAmount) revert NotEnoughGo();

		// Go Emissions
		goLastRewardTimestamp = block.timestamp;
		goEmissionFinalTimestamp = block.timestamp + _emissionDuration;
		goPerSecond = _emissionAmount / _emissionDuration;
		emit InitializedGOEmission(goPerSecond);

		// Go Staking
		_add(IERC20(_go), 10000);
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
		if (_boost < 10000 || _boost > 30000) revert OutsideRange();
		_updateGoRewardPerShare();
		stakingTokenData[_lp].boost = _boost;
		emit UpdatedLpBoost(_lp, _boost);
	}

	// UTILS

	function _getTotalStaked() internal view returns (uint256 staked) {
		staked = 0;
		for (uint256 i = 0; i < stakingTokens.values().length; i++) {
			staked += stakingTokenData[stakingTokens.at(i)].total * stakingTokenData[stakingTokens.at(i)].boost;
		}
	}

	function _getUserStaked(address _user) internal view returns (uint256 userStaked) {
		userStaked = 0;
		for (uint256 i = 0; i < stakingTokens.values().length; i++) {
			userStaked +=
				stakingTokenData[stakingTokens.at(i)].userStaked[_user] *
				stakingTokenData[stakingTokens.at(i)].boost;
		}
	}

	// AUCTION INTERACTIONS

	function receiveUSDDistribution() external override {
		// Nothing yet staked, leave the USD in here, it'll get scooped up in the next distribution
		uint256 totalStaked = _getTotalStaked();
		if (totalStaked == 0) return;

		uint256 currentUSDBal = USD.balanceOf(address(this));
		uint256 increase = currentUSDBal - markedUSDBal;

		usdRewardPerShare += (increase * REWARD_PRECISION) / totalStaked;
		markedUSDBal = currentUSDBal;

		emit ReceivedUSDDistribution(increase);
	}

	function getUserStakedGOBalance(address _user) external view override returns (uint256) {
		return _getUserStaked(_user);
	}

	// CORE

	function deposit(address _token, uint256 _amount) public nonReentrant {
		if (_amount > IERC20(_token).balanceOf(msg.sender)) revert BadDeposit();
		if (!stakingTokens.contains(_token)) revert NotStakeable();

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
		if (!stakingTokens.contains(_token)) revert NotStakeable();

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
		uint256 userStaked = _getUserStaked(_user);

		userDebtGO[_user] = (userStaked * goRewardPerShare) / REWARD_PRECISION;
		userDebtUSD[_user] = (userStaked * usdRewardPerShare) / REWARD_PRECISION;
	}

	function _getPendingUSD(address _user) internal view returns (uint256) {
		return ((_getUserStaked(_user) * usdRewardPerShare) / REWARD_PRECISION) - userDebtGO[_user];
	}

	function min(uint256 a, uint256 b) internal pure returns (uint256) {
		return a <= b ? a : b;
	}

	function _getUpdatedGoRewardPerShare() internal view returns (uint256 updatedGoRewardPerShare) {
		if (block.timestamp <= goLastRewardTimestamp) return goRewardPerShare;
		if (goLastRewardTimestamp >= goEmissionFinalTimestamp) return goRewardPerShare;

		uint256 totalStaked = _getTotalStaked();
		if (totalStaked == 0) return goRewardPerShare;

		// Take into account last emission block when calculating multiplier
		uint256 multiplier = min(block.timestamp, goEmissionFinalTimestamp) - goLastRewardTimestamp;
		uint256 emission = goPerSecond * multiplier;
		return goRewardPerShare + (emission * REWARD_PRECISION) / totalStaked;
	}

	function _updateGoRewardPerShare() internal {
		goRewardPerShare = _getUpdatedGoRewardPerShare();
		goLastRewardTimestamp = block.timestamp;
	}

	function _getPendingGO(address _user) internal view returns (uint256) {
		return ((_getUserStaked(_user) * _getUpdatedGoRewardPerShare()) / REWARD_PRECISION) - userDebtGO[_user];
	}

	function _harvest(address _user) internal {
		// USD
		uint256 pendingUSD = _getPendingUSD(_user);
		USD.safeTransfer(msg.sender, pendingUSD);
		markedUSDBal = USD.balanceOf(address(this));

		// Update Go Reward Per Share
		_updateGoRewardPerShare();

		// GO
		uint256 pendingGO = _getPendingGO(_user);
		GO.safeTransfer(msg.sender, pendingGO);

		emit Harvested(msg.sender, pendingUSD, pendingGO);
	}

	function harvest() public nonReentrant {
		_harvest(msg.sender);
		_updateUserDebts(msg.sender);
	}

	function pending(address _user) public view returns (uint256 pendingUSD, uint256 pendingGO) {
		pendingUSD = _getPendingUSD(_user);
		pendingGO = _getPendingGO(_user);
	}
}
