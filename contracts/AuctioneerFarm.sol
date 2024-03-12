// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./IAuctioneerFarm.sol";

contract AuctioneerFarm is Ownable, ReentrancyGuard, IAuctioneerFarm {
	using SafeERC20 for IERC20;

	IERC20 public GO;
	IERC20 public USD;
	IERC20 public GO_LP;
	uint256 public lockPeriod;

	uint256 public REW_PRECISION = 1e18;

	// USD rewards from auctions
	uint256 public usdBal;
	uint256 public usdRewardPerShare;

	// GO rewards from staking
	uint256 public goPerSecond = 0;
	uint256 public goRewardPerShare;
	uint256 public goLastRewardTimestamp;
	uint256 public goEmissionFinalTimestamp;

	// Deposits
	uint256 public totalDepositedAmount;
	uint256 public totalDepositedAmountLP;
	uint256 public lpBonus = 20000;

	struct UserInfo {
		uint256 amount;
		uint256 amountLP;
		uint256 debtUSD;
		uint256 debtGO;
	}
	mapping(address => UserInfo) public userInfo;

	error DepositStillLocked();
	error BadWithdrawal();
	error BadDeposit();
	error OutsideRange();
	error NotEnoughGo();
	error AlreadySet();

	event InitializedGOEmission(uint256 _goPerSecond);
	event UpdatedLPBonus(uint256 _lpBonus);
	event ReceivedUSDDistribution(uint256 _amount);

	event Deposit(address indexed _user, uint256 _amount, uint256 _amountLP);
	event Withdraw(address indexed _user, uint256 _amount, uint256 _amountLP);
	event Harvested(address indexed _user, uint256 _usdHarvested, uint256 _goHarvested);

	constructor() Ownable(msg.sender) {}

	// ADMIN

	// One time GO emission initialization
	function setGOEmission(uint256 _emissionAmount, uint256 _duration) public onlyOwner {
		if (GO.balanceOf(address(this)) < _emissionAmount) revert NotEnoughGo();
		if (goPerSecond > 0) revert AlreadySet();

		goLastRewardTimestamp = block.timestamp;
		goEmissionFinalTimestamp = block.timestamp + _duration;
		goPerSecond = _emissionAmount / _duration;

		emit InitializedGOEmission(goPerSecond);
	}

	function setLPBonus(uint256 _lpBonus) public onlyOwner {
		if (_lpBonus < 10000 || _lpBonus > 30000) revert OutsideRange();

		lpBonus = _lpBonus;
		emit UpdatedLPBonus(_lpBonus);
	}

	// UTILS

	function _userEffectiveStaked(UserInfo memory user) internal view returns (uint256) {
		return user.amount + (user.amountLP * lpBonus) / 10000;
	}
	function _totalEffectiveStaked() internal view returns (uint256) {
		return totalDepositedAmount + (totalDepositedAmountLP * lpBonus) / 10000;
	}

	function _updateUserDebts(UserInfo memory user) internal view {
		user.debtUSD = (_userEffectiveStaked(user) * usdRewardPerShare) / REW_PRECISION;
		user.debtGO = (_userEffectiveStaked(user) * goRewardPerShare) / REW_PRECISION;
	}

	// AUCTION INTERACTIONS

	function receiveUSDDistribution() external override {
		// Nothing yet staked, leave the USD in here, it'll get scooped up in the next distribution
		if (_totalEffectiveStaked() == 0) return;

		uint256 newBal = USD.balanceOf(address(this));
		uint256 increase = newBal - usdBal;
		usdRewardPerShare += (increase * REW_PRECISION) / _totalEffectiveStaked();
		usdBal = newBal;

		emit ReceivedUSDDistribution(increase);
	}

	function getUserStakedGOBalance(address _user) external view override returns (uint256) {
		return _userEffectiveStaked(userInfo[_user]);
	}

	// DEPOSIT

	function depositAll() external {
		deposit(GO.balanceOf(msg.sender), GO_LP.balanceOf(msg.sender));
	}
	function deposit(uint256 _amount, uint256 _amountLP) public nonReentrant {
		if (_amount > GO.balanceOf(msg.sender)) revert BadDeposit();
		if (address(GO_LP) != address(0) && _amountLP > GO_LP.balanceOf(msg.sender)) revert BadDeposit();

		UserInfo storage user = userInfo[msg.sender];
		_harvest(user);

		if (_amount > 0) {
			GO.safeTransferFrom(msg.sender, address(this), _amount);
		}
		if (address(GO_LP) != address(0) && _amountLP > 0) {
			GO_LP.safeTransferFrom(msg.sender, address(this), _amountLP);
		}

		user.amount += _amount;
		user.amountLP += _amountLP;
		totalDepositedAmount += _amount;
		totalDepositedAmountLP += _amountLP;

		// (MUST SET DEBT AFTER DEPOSIT - user.amount has been increased)
		_updateUserDebts(user);

		emit Deposit(msg.sender, _amount, _amountLP);
	}

	// WITHDRAW

	function withdrawAll() external {
		withdraw(userInfo[msg.sender].amount, userInfo[msg.sender].amountLP);
	}
	function withdraw(uint256 _amount, uint256 _amountLP) public nonReentrant {
		UserInfo storage user = userInfo[msg.sender];
		if (_amount > user.amount) revert BadWithdrawal();
		if (_amountLP > user.amountLP) revert BadWithdrawal();

		_harvest(user);

		if (_amount > 0) {
			user.amount -= _amount;
			totalDepositedAmount -= _amount;
			GO.safeTransfer(msg.sender, _amount);
		}
		if (_amountLP > 0) {
			user.amountLP -= _amountLP;
			totalDepositedAmountLP -= _amountLP;
			GO_LP.safeTransfer(msg.sender, _amountLP);
		}

		// (MUST SET DEBT AFTER WITHDRAWAL - user.amount has been reduced)
		_updateUserDebts(user);

		emit Withdraw(msg.sender, _amount, _amountLP);
	}

	// HARVEST

	function _pendingUSD(UserInfo memory user) internal view returns (uint256) {
		return ((_userEffectiveStaked(user) * usdRewardPerShare) / REW_PRECISION) - user.debtGO;
	}

	function _pendingGO(UserInfo memory user) internal returns (uint256) {
		uint256 totalStaked = _totalEffectiveStaked();

		// Must take into account streaming emissions, and update goRewardPerShare
		if (block.timestamp > goLastRewardTimestamp && totalStaked != 0) {
			uint256 emission = goPerSecond * (block.timestamp - goLastRewardTimestamp);
			goRewardPerShare = goRewardPerShare + (emission * REW_PRECISION) / totalStaked;
		}

		return ((_userEffectiveStaked(user) * goRewardPerShare) / REW_PRECISION) - user.debtGO;
	}

	function _harvest(UserInfo storage user) internal {
		// USD
		uint256 pendingUSD = _pendingUSD(user);
		USD.safeTransfer(msg.sender, pendingUSD);
		usdBal -= pendingUSD;

		// GO
		uint256 pendingGO = _pendingGO(user);
		GO.safeTransfer(msg.sender, pendingGO);

		emit Harvested(msg.sender, pendingUSD, pendingGO);
	}

	function harvest() public nonReentrant {
		UserInfo storage user = userInfo[msg.sender];

		_harvest(user);
		_updateUserDebts(user);
	}

	function pending(address _user) public returns (uint256 pendingUSD, uint256 pendingGO) {
		pendingUSD = _pendingUSD(userInfo[_user]);
		pendingGO = _pendingGO(userInfo[_user]);
	}
}
