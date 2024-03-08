// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./IAuctioneerFarm.sol";

contract AuctioneerFarm is Ownable, ReentrancyGuard, IAuctioneerFarm {
    using SafeERC20 for IERC20;

    IERC20 public GO;
    IERC20 public USD;
    uint256 usdBal;
    uint256 public lockPeriod;

    uint256 public rewardPerShare;
    uint256 public totalDepositedAmount;
    uint256 public REW_PRECISION = 1e18;

    struct UserInfo {
        uint256 amount;
        uint256 debt;
    }
    mapping(address => UserInfo) public userInfo;

    error DepositStillLocked();
    error BadWithdrawal();
    error BadDeposit();

    event Deposit(address indexed _user, uint256 _amount);
    event Withdraw(address indexed _user, uint256 _amount);
    event ReceivedUSDDistribution(uint256 _amount);

    constructor () Ownable(msg.sender) {}

    // AUCTION INTERACTIONS

    function receiveUSDDistribution() external override {
        uint256 newBal = USD.balanceOf(address(this));
        uint256 increase = newBal - usdBal;
        rewardPerShare += (increase * REW_PRECISION) / totalDepositedAmount;
        usdBal = newBal;
        emit ReceivedUSDDistribution(increase);
    }

    function getUserStakedGOBalance(address _user) external override view returns (uint256) {
        return userInfo[_user].amount;
    }


    // DEPOSIT

    function depositAll() external {
        deposit(GO.balanceOf(msg.sender));
    }
    function deposit(uint _amount) public nonReentrant {
        if (_amount > GO.balanceOf(msg.sender)) revert BadDeposit();

        UserInfo storage user = userInfo[msg.sender];
        GO.safeTransferFrom(msg.sender, address(this), _amount);

        // Harvest USD rewards (MUST SET DEBT AFTER DEPOSIT - user.amount yet to increase)
        harvest();

        user.amount += _amount;
        totalDepositedAmount += _amount;

        // (MUST SET DEBT AFTER DEPOSIT - user.amount has been increased)
        user.debt = user.amount * rewardPerShare / REW_PRECISION;

        emit Deposit(msg.sender, _amount);
    }

    // WITHDRAW

    function withdrawAll() external {
        withdraw(userInfo[msg.sender].amount);
    }
    function withdraw(uint256 _amount) public nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        if (_amount > user.amount) revert BadWithdrawal();

        // Harvest USD rewards (MUST SET DEBT AFTER WITHDRAWAL - user.amount yet to reduce)
        harvest();

        if (_amount > 0) {
            user.amount -= _amount;
            totalDepositedAmount -= _amount;
            GO.safeTransfer(msg.sender, _amount);
        }

        // (MUST SET DEBT AFTER WITHDRAWAL - user.amount has been reduced)
        user.debt = user.amount * rewardPerShare / REW_PRECISION;

        emit Withdraw(msg.sender, _amount);
    }

    // HARVEST

    function harvest() public nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        uint256 reward = user.amount * rewardPerShare / REW_PRECISION;
        uint256 pending = reward - user.debt;
        USD.safeTransfer(msg.sender, pending);
        usdBal -= pending;

        user.debt = user.amount * rewardPerShare / REW_PRECISION;
    }
}