// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

interface IVaultReceiver {
  function receiveCut(uint256 _amount) external;
}