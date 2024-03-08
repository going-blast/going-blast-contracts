// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

enum BidWindowType { OPEN, TIMED, INFINITE }

// Params

struct BidWindowParams {
  BidWindowType windowType;
  uint256 duration;
  uint256 timer;
}

struct AuctionParams {
  bool isPrivate;
  uint256 emissionBP; // Emission of this auction of the day's emission (usually 100%)
  IERC20[] tokens;
  uint256[] amounts;
  string name;
  BidWindowParams[] windows;
  uint256 unlockTimestamp;
}

// Storage

struct BidWindow {
  BidWindowType windowType;
  uint256 windowOpenTimestamp;
  uint256 windowCloseTimestamp; // 0 for window that goes forever
  uint256 timer; // 0 for no timer, >60 for other timers (1m / 2m / 5m)
}

struct Auction {
  uint256 lot;
  bool isPrivate; // whether the auction requires wallet / staked Gavel
  uint256 biddersEmission; // token to be distributed through auction to bidders
  uint256 treasuryEmission; // token to be distributed to treasury at end of auction (10% of total emission)
  BidWindow[] windows;
  uint256 unlockTimestamp;

  string name;
  IERC20[] tokens;
  uint256[] amounts;
  
  uint256 sum;
  uint256 bid;
  uint256 bidTimestamp;
  address bidUser;
  uint256 bids; // number of bids during auction

  bool claimed;
  bool finalized;
}

struct AuctionUser {
  uint256 bids;
  bool claimed;
}

error TooManyAuctions();
error InvalidEmissionBP();
error InvalidAuctionLot();
error InvalidWindowOrder();
error WindowTooShort();
error InvalidBidWindowCount();
error InvalidBidWindowTimer();
error LastWindowNotInfinite();
error MultipleInfiniteWindows();
error TooManyTokens();
error LengthMismatch();
error BiddingClosed();
error AuctionStillRunning();
error NoTokens();
error AuctionClosed();
error NotCancellable();
error TooSteep();
error ZeroAddress();
error PrivateAuction();
error UnlockAlreadyPassed();
error BadDeposit();
error BadWithdrawal();

interface IAuctioneer {

  event AuctionCreated(uint256 indexed _lot);
  event Bid(uint256 indexed _lot, address indexed _user, uint256 _bid);
  event AuctionFinalized(uint256 indexed _lot);
  event AuctionLotClaimed(uint256 indexed _lot, address indexed _user, IERC20[] _tokens, uint256[] _amounts);
  event UserClaimedLotEmissions(uint256 _lot, address indexed _user, uint256 _emissions);
  event AuctionCancelled(uint256 indexed _lot, address indexed _owner);
  event UpdatedTreasury(address indexed _treasury);
  event UpdatedFarm(address indexed _farm);
  event UpdatedTreasurySplit(uint256 _split);
  event UpdatedPrivateAuctionRequirement(uint256 _requirement);
  event InitializedAuctions();
  event AddedBalance(address _user, uint256 _amount);
  event WithdrewBalance(address _user, uint256 _amount);
  
}