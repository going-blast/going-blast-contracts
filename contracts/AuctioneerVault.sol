// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IVaultReceiver.sol";

contract AuctioneerVault is Ownable, ReentrancyGuard, IVaultReceiver {
    using SafeERC20 for IERC20;

    IERC20 public auctionToken;
    uint256 public lockPeriod;

    uint256 public totalShares = 0;
    mapping(address => uint256) public userShares;
    mapping(address => uint256) public userDepositTimestamp;

    error DepositStillLocked();
    error BadWithdrawal();
    error BadDeposit();

    constructor () Ownable(msg.sender) {}

    
    function vaultBalance() public view returns (uint256) {
        return auctionToken.balanceOf(address(this));
    }

    function getPricePerFullShare() public view returns (uint256) {
        return totalShares == 0 ? 1e18 : vaultBalance() * 1e18 / totalShares;
    }

    
    function depositAll() external {
        deposit(auctionToken.balanceOf(msg.sender));
    }
    function deposit(uint _amount) public nonReentrant {
        if (_amount > auctionToken.balanceOf(msg.sender)) revert BadDeposit();
        auctionToken.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 shares = 0;
        if (totalShares == 0) {
            shares = _amount;
        } else {
            shares = (_amount * totalShares) / 1; // todo fix this what should the 1 actually
        }
        
        userShares[msg.sender] += shares;
        totalShares += shares;
        userDepositTimestamp[msg.sender] = block.timestamp;
    }


    function withdrawAll() external {
        withdraw(userShares[msg.sender]);
    }
    function withdraw(uint256 _shares) public {
        if (_shares > userShares[msg.sender]) revert BadWithdrawal();
        if (block.timestamp < (userDepositTimestamp[msg.sender] + lockPeriod)) revert DepositStillLocked();

        uint256 r = (vaultBalance() * _shares) / totalShares;

        userShares[msg.sender] -= r;
        totalShares -= r;

        auctionToken.safeTransfer(msg.sender, r);
    }




    function receiveCut(uint256 _amount) public {
      // TODO: Do something with this here
    }
}