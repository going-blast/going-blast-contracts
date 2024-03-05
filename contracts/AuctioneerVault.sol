// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./IVaultReceiver.sol";

contract AuctioneerVault is Ownable, ReentrancyGuard, IVaultReceiver {
    using SafeERC20 for IERC20;

    IERC20 public GAVEL;
    IERC20 public USD;
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
    event ReceivedCut(uint256 _amount);

    constructor () Ownable(msg.sender) {}

    function receiveCut(uint256 _amount) public {
        rewardPerShare += (_amount * REW_PRECISION) / totalDepositedAmount;
        emit ReceivedCut(_amount);
    }

    // DEPOSIT

    function depositAll() external {
        deposit(GAVEL.balanceOf(msg.sender));
    }
    function deposit(uint _amount) public nonReentrant {
        if (_amount > GAVEL.balanceOf(msg.sender)) revert BadDeposit();
        GAVEL.safeTransferFrom(msg.sender, address(this), _amount);

        UserInfo storage user = userInfo[msg.sender];
        user.amount += _amount;
        user.debt = user.amount * rewardPerShare / REW_PRECISION;

        totalDepositedAmount += user.amount;

        emit Deposit(msg.sender, _amount);
    }

    // WITHDRAW

    function withdrawAll() external {
        withdraw(userInfo[msg.sender].amount);
    }
    function withdraw(uint256 _amount) public nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        if (_amount > user.amount) revert BadWithdrawal();

        uint256 reward = user.amount * rewardPerShare / REW_PRECISION;
        uint256 pending = reward - user.debt;
        USD.safeTransfer(msg.sender, pending);

        if (_amount > 0) {
            user.amount -= _amount;
            totalDepositedAmount -= _amount;
            GAVEL.safeTransfer(msg.sender, _amount);
        }

        user.debt = user.amount * rewardPerShare / REW_PRECISION;

        emit Withdraw(msg.sender, _amount);
    }
}