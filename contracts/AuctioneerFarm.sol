// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./IAuctioneerFarm.sol";

contract AuctioneerFarm is Ownable, ReentrancyGuard, IAuctioneerFarm, AuctioneerFarmEvents {
	using SafeERC20 for IERC20;
	using EnumerableSet for EnumerableSet.AddressSet;

	bool public initializedEmissions = false;
	uint256 public constant REWARD_PRECISION = 1e18;

	IERC20 public USD;
	IERC20 public GO;
	IERC20 public BID;
	mapping(address => TokenEmission) public emissionData;

	// Staking
	EnumerableSet.AddressSet internal stakingTokens;
	mapping(address => StakingTokenData) public stakingTokenData;
	uint256 public totalAlloc;
	mapping(address => uint256) public userDebtGO;
	mapping(address => uint256) public userDebtBID;
	mapping(address => uint256) public userDebtUSD;

	constructor(IERC20 _usd, IERC20 _go, IERC20 _bid) Ownable(msg.sender) {
		USD = _usd;
		emissionData[address(USD)] = TokenEmission({
			token: address(USD),
			emissionType: EmissionType.CHUNK,
			rewPerSecond: 0,
			lastRewardTimestamp: 0,
			emissionFinalTimestamp: 0
		});
		GO = _go;
		emissionData[address(GO)] = TokenEmission({
			token: address(GO),
			emissionType: EmissionType.DRIP,
			rewPerSecond: 0,
			lastRewardTimestamp: 0,
			emissionFinalTimestamp: 0
		});
		BID = _bid;
		emissionData[address(BID)] = TokenEmission({
			token: address(BID),
			emissionType: EmissionType.DRIP,
			rewPerSecond: 0,
			lastRewardTimestamp: 0,
			emissionFinalTimestamp: 0
		});
	}

	// GO emissions are a one time thing, can't be updated
	function initializeEmissions(uint256 _emissionAmount, uint256 _emissionDuration) public onlyOwner {
		if (initializedEmissions) revert AlreadyInitializedEmissions();
		initializedEmissions = true;

		_setEmissions(emissionData[address(GO)], _emissionAmount, _emissionDuration);
		emit InitializedGOEmission(emissionData[address(GO)].rewPerSecond, _emissionDuration);

		// Go Staking
		_add(GO, 10000);
	}

	function setBIDEmissions(uint256 _emissionAmount, uint256 _emissionDuration) public onlyOwner {
		_bringDripEmissionsCurrent(emissionData[address(BID)]);
		_setEmissions(emissionData[address(BID)], _emissionAmount, _emissionDuration);
		emit UpdatedBIDEmission(emissionData[address(BID)].rewPerSecond, _emissionDuration);
	}

	// ADMIN

	function _add(IERC20 _token, uint256 _boost) internal {
		bringAllDripEmissionsCurrent();
		stakingTokens.add(address(_token));
		stakingTokenData[address(_token)].token = _token;
		stakingTokenData[address(_token)].boost = _boost;
		totalAlloc += _boost;
		emit AddedStakingToken(address(_token), _boost);
	}

	function addLp(address _lp, uint256 _boost) public onlyOwner {
		if (stakingTokens.contains(_lp)) revert AlreadyAdded();
		if (_boost < 10000 || _boost > 30000) revert OutsideRange();
		_add(IERC20(_lp), _boost);
	}

	function removeLp(address _lp) public onlyOwner {
		bringAllDripEmissionsCurrent();
		totalAlloc -= stakingTokenData[_lp].boost;
		stakingTokenData[_lp].boost = 0;
		emit UpdatedLpBoost(_lp, 0);
	}

	function updateLpBoost(address _lp, uint256 _boost) public onlyOwner {
		if (!stakingTokens.contains(_lp)) revert NotStakingToken();
		if (_boost < 10000 || _boost > 30000) revert OutsideRange();
		bringAllDripEmissionsCurrent();
		totalAlloc = totalAlloc - stakingTokenData[_lp].boost + _boost;
		stakingTokenData[_lp].boost = _boost;
		emit UpdatedLpBoost(_lp, _boost);
	}

	// UTILS

	// Used only externally to test if user permitted to enter private auctions
	// Rewards are calculated differently
	function _getEqualizedTotalStaked() internal view returns (uint256 staked) {
		staked = 0;
		for (uint256 i = 0; i < stakingTokens.values().length; i++) {
			staked += stakingTokenData[stakingTokens.at(i)].total * stakingTokenData[stakingTokens.at(i)].boost;
		}
		staked /= 10000;
	}

	// Used only externally to test if user permitted to enter private auctions
	// Rewards are calculated differently
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
		_distributeEmissions(address(USD), _amount);

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

		_updateAllUserDebts(msg.sender);

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

		_updateAllUserDebts(msg.sender);

		emit Withdraw(msg.sender, _token, _amount);
	}

	// HARVEST

	function _updateAllUserDebts(address _user) internal {
		_updateUserDebts(address(USD), _user);
		_updateUserDebts(address(GO), _user);
		_updateUserDebts(address(BID), _user);
	}

	function _updateUserDebts(address _emissionToken, address _user) internal {
		for (uint8 i = 0; i < stakingTokens.values().length; i++) {
			stakingTokenData[stakingTokens.at(i)].userEmissionDebt[_user][_emissionToken] =
				stakingTokenData[stakingTokens.at(i)].userStaked[_user] *
				stakingTokenData[stakingTokens.at(i)].emissionRewPerShare[_emissionToken];
		}
	}

	function _pending(address _user) internal returns (PendingAmounts memory pendingAmounts) {
		bringAllDripEmissionsCurrent();
		pendingAmounts.usd = _getUserEmissionsPending(address(USD), _user);
		pendingAmounts.go = _getUserEmissionsPending(address(GO), _user);
		pendingAmounts.bid = _getUserEmissionsPending(address(BID), _user);
	}

	function bringAllDripEmissionsCurrent() internal {
		_bringDripEmissionsCurrent(emissionData[address(GO)]);
		_bringDripEmissionsCurrent(emissionData[address(BID)]);
	}

	function _harvest(address _user) internal {
		PendingAmounts memory pendingAmounts = _pending(_user);
		if (pendingAmounts.usd > 0) USD.safeTransfer(msg.sender, pendingAmounts.usd);
		if (pendingAmounts.go > 0) GO.safeTransfer(msg.sender, pendingAmounts.go);
		if (pendingAmounts.bid > 0) BID.safeTransfer(msg.sender, pendingAmounts.bid);
		emit Harvested(msg.sender, pendingAmounts);
	}

	function harvest() public nonReentrant {
		_harvest(msg.sender);
		_updateAllUserDebts(msg.sender);
	}

	function pending(address _user) public returns (PendingAmounts memory pendingAmounts) {
		return _pending(_user);
	}

	function getEmissionData(address _token) public view returns (TokenEmission memory tokenEmissionData) {
		tokenEmissionData = emissionData[_token];
	}

	function getStakingTokenEmissionRewPerShare(
		address _stakingToken,
		address _emissionToken
	) public returns (uint256 state, uint256 current) {
		state = stakingTokenData[_stakingToken].emissionRewPerShare[_emissionToken];
		_bringDripEmissionsCurrent(emissionData[_emissionToken]);
		current = stakingTokenData[_stakingToken].emissionRewPerShare[_emissionToken];
	}

	// EMISSIONS

	function min(uint256 a, uint256 b) internal pure returns (uint256) {
		return a <= b ? a : b;
	}

	function _distributeEmissions(address _token, uint256 _emission) internal {
		for (uint8 i = 0; i < stakingTokens.values().length; i++) {
			if (stakingTokenData[stakingTokens.at(i)].total > 0) {
				stakingTokenData[stakingTokens.at(i)].emissionRewPerShare[_token] +=
					(_emission * REWARD_PRECISION * stakingTokenData[stakingTokens.at(i)].boost) /
					(totalAlloc * stakingTokenData[stakingTokens.at(i)].total);
			}
		}
	}

	function _bringDripEmissionsCurrent(TokenEmission storage tokenEmission) internal {
		if (tokenEmission.token == address(0)) return;
		if (tokenEmission.emissionType != EmissionType.DRIP) return;
		if (block.timestamp <= tokenEmission.lastRewardTimestamp) return;
		if (tokenEmission.lastRewardTimestamp >= tokenEmission.emissionFinalTimestamp) return;

		// Take into account last emission block when calculating multiplier
		uint256 multiplier = min(block.timestamp, tokenEmission.emissionFinalTimestamp) - tokenEmission.lastRewardTimestamp;
		uint256 emission = tokenEmission.rewPerSecond * multiplier;

		// Give emissions to each staking token based on their alloc
		_distributeEmissions(tokenEmission.token, emission);
	}

	function _getUserEmissionsPending(address _emissionToken, address _user) internal view returns (uint256 userPending) {
		StakingTokenData storage tokenData;
		for (uint8 i = 0; i < stakingTokens.values().length; i++) {
			tokenData = stakingTokenData[stakingTokens.at(i)];
			userPending +=
				((tokenData.userStaked[_user] * tokenData.emissionRewPerShare[_emissionToken]) -
					tokenData.userEmissionDebt[_user][_emissionToken]) /
				1e18;
		}
	}

	function _setEmissions(TokenEmission storage tokenEmission, uint256 _amount, uint256 _duration) internal {
		tokenEmission.lastRewardTimestamp = block.timestamp;
		tokenEmission.emissionFinalTimestamp = block.timestamp + _duration;
		tokenEmission.rewPerSecond = _amount / _duration;

		if (IERC20(tokenEmission.token).balanceOf(address(this)) < _amount) revert IAuctioneerFarm.NotEnoughEmissionToken();
	}
}
