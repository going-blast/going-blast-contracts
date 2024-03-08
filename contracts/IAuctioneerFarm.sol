// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

interface IAuctioneerFarm {
  function receiveUSDDistribution() external;
  function getUserStakedGOBalance(address _user) external view returns (uint256);
}