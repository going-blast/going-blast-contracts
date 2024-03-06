// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { GavelToken } from "./GavelToken.sol";
import "./IVaultReceiver.sol";


enum BidWindowType { OPEN, TIMED, INFINITE }
enum AuctionState{ WAITING, OPEN, FINALIZED }

struct BidWindow {
  BidWindowType windowType;
  uint256 windowOpenTimestamp;
  uint256 windowCloseTimestamp; // 0 for window that goes forever
  uint256 timer; // 0 for no timer, >60 for other timers (1m / 2m / 5m)
}
struct BidWindowParams {
  BidWindowType windowType;
  uint256 duration;
  uint256 timer;
}

struct Auction {
  uint256 lot;
  bool isPrivate; // whether the auction requires wallet / staked Gavel
  uint256 emission; // token to be distributed through auction
  BidWindow[] windows;
  uint256 unlockTimestamp;

  string name;
  IERC20[] tokens;
  uint256[] amounts;
  
  uint256 sum;
  uint256 bid;
  uint256 bidTimestamp;
  address bidUser;
  uint256 points; // sum of all points generated during auction

  bool claimed;
  AuctionState state;
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

struct AuctionUser {
  uint256 points;
  bool claimed;
}

// 6 hour initial bidding window
// Quick bid 2 hours (5 minute timer)
// Super quick bid (2 minute timer to Inf)
// MON-FRI normal public auctions (500 - 1k)
// SAT public big auction (3-5k)
// SUN private big auction (4-6k)

contract Auctioneer is Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    // CORE
    Auction[] public auctions;
    mapping(uint256 => mapping(address => AuctionUser)) public auctionUsers;
    uint256 public startTimestamp;
    uint256 epochDuration = 90 days;

    // BID PARAMS
    IERC20 public USD;
    uint256 public bidIncrement;
    uint256 public startingBid;
    uint256 public privateAuctionRequirement;
    uint256 public onceTwiceBlastBonusTime = 9;

    // EMISSIONS
    IERC20 public GO;
    uint256[8] emissionSharePerEpoch = [128, 64, 32, 16, 8, 4, 2, 1];
    uint256 emissionSharesTotal = 255;
    uint256 emissionPerShare = 255e18;

    uint256 bidPoints; // gas savings to prevent reassignment

    address public treasury;
    address public farm;
    uint256 public treasurySplit = 5000;

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
    error NoTokens();
    error AuctionClosed();
    error NotCancellable();
    error TooSteep();
    error ZeroAddress();
    error PrivateAuction();
    error UnlockAlreadyPassed();

    event EmissionOnBidUpdated(uint256 _emissionOnBid);
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
    event StartedGoingBlast();

    constructor(IERC20 _usd, uint256 _bidIncrement, uint256 _startingBid, uint256 _privateRequirement) Ownable(msg.sender) {
      USD = _usd;
      bidIncrement = _bidIncrement;
      startingBid = _startingBid;
      privateAuctionRequirement = _privateRequirement;
    }

    // MODIFIERS


    modifier validAuctionLot(uint256 _lot) {
      if (_lot >= auctions.length) revert InvalidAuctionLot();
      _;
    }

    // SETTERS

    function setTreasury(address _treasury) public onlyOwner {
      if (_treasury == address(0)) revert ZeroAddress();
      treasury = _treasury;
      emit UpdatedTreasury(_treasury);
    }

    function setFarm(address _farm) public onlyOwner {
      farm = _farm;
      emit UpdatedFarm(_farm);
    }

    function setTreasurySplit(uint256 _treasurySplit) public onlyOwner {
      if (_treasurySplit > 5000) revert TooSteep();
      treasurySplit = _treasurySplit;
      emit UpdatedTreasurySplit(_treasurySplit);
    }

    function updatePrivateAuctionRequirement(uint256 _requirement) public onlyOwner {
      privateAuctionRequirement = _requirement;
      emit UpdatedPrivateAuctionRequirement(_requirement);
    }

    // CORE

    function start(uint256 _unlockTimestamp) internal {
      startTimestamp = _unlockTimestamp;
      emit StartedGoingBlast();
    }

    function createDailyAuctions(AuctionParams[] memory _params) public onlyOwner nonReentrant {
      if (_params.length > 4) revert TooManyAuctions();

      uint256 totalEmissionBP = 0;
      for (uint8 i = 0; i < _params.length; i++) {
        totalEmissionBP += _params[i].emissionBP;
      }

      // Most days, this will be 10000, an emission BP over 10000 means it is using emissions scheduled for other days
      // Auctions for the remainder of the epoch will be reduced
      // This will never overflow the emissions though, because the emission amount is calculated from remaining emissions
      if (totalEmissionBP > 20000) revert InvalidEmissionBP();

      for (uint8 i = 0; i < _params.length; i++) {
        _createSingleAuction(_params[i]);
      }
    }

    function _getEmissionForAuction(uint256 _bp) internal pure returns (uint256) {
      // Get epoch
      // Get number of days remaining in epoch
      // day emission = Epoch emission / num days remaining
      // return day emission * _bp / 10000
      // unused emissions roll over to the remaining days
      return _bp;
    }

    // Transformation from params is a gas saving measure via caching the window start and end timestamps
    // Validation of window parameters
    function _transformAuctionBidWindows(AuctionParams memory _params) internal view returns (BidWindow[] memory) {
      if (_params.unlockTimestamp < block.timestamp) revert UnlockAlreadyPassed();

      // YES I KNOW that this is inefficient, this is an owner facing function.
      // Legibility and clarity > once daily gas price.

      // VALIDATE: Windows must flow from open -> timed -> infinite
      BidWindowType runningType = BidWindowType.OPEN;
      for (uint8 i = 0; i < _params.windows.length; i++) {
        if (_params.windows[i].windowType < runningType) revert InvalidWindowOrder();
        runningType = _params.windows[i].windowType; 
      }

      // VALIDATE: Last window must be infinite window
      if (_params.windows[_params.windows.length - 1].windowType != BidWindowType.INFINITE) revert LastWindowNotInfinite();

      // VALIDATE: Only one infinite window can exist
      uint8 infCount = 0;
      for (uint8 i = 0; i < _params.windows.length; i++) {
        if (_params.windows[i].windowType == BidWindowType.INFINITE) infCount += 1;
      }
      if (infCount > 1) revert MultipleInfiniteWindows();

      // VALIDATE: Windows must have a valid duration (if not infinite)
      for (uint8 i = 0; i < _params.windows.length; i++) {
        if (_params.windows[i].windowType != BidWindowType.INFINITE && _params.windows[i].duration < 1 hours) revert WindowTooShort();
      }

      // VALIDATE: Timed windows must have a valid timer
      for (uint8 i = 0; i < _params.windows.length; i++) {
        if (_params.windows[i].windowType != BidWindowType.OPEN && _params.windows[i].timer < 60 seconds) revert InvalidBidWindowTimer();
      }

      // Add transformed windows to auction
      BidWindow[] memory windows = new BidWindow[](_params.windows.length);

      uint256 openTimestamp = _params.unlockTimestamp;
      for (uint8 i = 0; i < _params.windows.length; i++) {
        uint256 closeTimestamp = openTimestamp + _params.windows[i].duration;
        if (_params.windows[i].windowType == BidWindowType.INFINITE) {
          closeTimestamp = openTimestamp + 315600000; // 10 years, hah
        }

        windows[i] = BidWindow({
          windowType: _params.windows[i].windowType,
          windowOpenTimestamp: openTimestamp,
          windowCloseTimestamp: closeTimestamp,
          timer: _params.windows[i].timer + onceTwiceBlastBonusTime
        });

        openTimestamp += _params.windows[i].duration;
      }

      return windows;
    }

    function _createSingleAuction(AuctionParams memory _params) internal {
      if (_params.tokens.length > 4) revert TooManyTokens();
      if (_params.tokens.length != _params.amounts.length) revert LengthMismatch();
      if (_params.tokens.length == 0) revert NoTokens();
      if (_params.windows.length == 0 || _params.windows.length > 4) revert InvalidBidWindowCount();

      uint256 lot = auctions.length;
      if (lot == 0) start(_params.unlockTimestamp);

      // Transfer tokens from treasury
      for (uint8 i = 0; i < _params.tokens.length; i++) {
        _params.tokens[i].safeTransferFrom(treasury, address(this), _params.amounts[i]);
      }

      // Base Auction Data
      auctions.push(Auction({
        lot: auctions.length,
        isPrivate: _params.isPrivate,
        emission: _getEmissionForAuction(_params.emissionBP),
        windows: _transformAuctionBidWindows(_params),
        points: 0,

        tokens: _params.tokens,
        amounts: _params.amounts,
        name: _params.name,
        unlockTimestamp: _params.unlockTimestamp,
        
        sum: 0,
        bid: startingBid,
        bidTimestamp: _params.unlockTimestamp,
        bidUser: msg.sender,

        claimed: false,
        state: AuctionState.WAITING
      }));

      emit AuctionCreated(auctions.length - 1);      
    }

    function cancel(uint256 _lot) public validAuctionLot(_lot) nonReentrant onlyOwner {
      Auction storage auction = auctions[_lot];

      if (auction.bid > startingBid) revert NotCancellable();

      for (uint8 i = 0; i < auction.tokens.length; i++) {
        auction.tokens[i].safeTransfer(treasury, auction.amounts[i]);
      }
      auction.state = AuctionState.FINALIZED;

      emit AuctionCancelled(_lot, msg.sender);
    }




    function _getActiveWindow(Auction memory auction) internal view returns (int8) {
      // Before auction opens, active window is -1
      if (block.timestamp < auction.unlockTimestamp) return -1;
      
      // Check if timestamp is before the end of each window, if it is, return that windows index
      for (uint8 i = 0; i < auction.windows.length; i++) {
        if (block.timestamp < auction.windows[i].windowCloseTimestamp) return int8(i);
      }

      // Shouldn't ever get here, maybe in 10 years or so.
      return int8(uint8(auction.windows.length - 1));
    }

    function _getIsBiddingOpen(Auction memory auction) internal view returns (bool) {
      // Early escape if the auction has been finalized
      if (auction.state == AuctionState.FINALIZED) return false;

      int8 activeWindow = _getActiveWindow(auction);

      if (activeWindow == -1) return false;
      if (auction.windows[uint256(uint8(activeWindow))].windowType == BidWindowType.OPEN) return true;

      // TODO: gas optimize
      uint256 windowOpen = auction.windows[uint256(uint8(activeWindow))].windowOpenTimestamp;
      uint256 lastBid = auction.bidTimestamp;
      uint256 auctionWouldCloseAt = (windowOpen > lastBid ? windowOpen : lastBid) + auction.windows[uint256(uint8(activeWindow))].timer;

      return block.timestamp < auctionWouldCloseAt;
    }



    function _getHasAuctionClosed(Auction storage auction) internal view returns (bool) {
      // Early escape if the auction has been finalized
      if (auction.state == AuctionState.FINALIZED) return false;

      int8 activeWindow = _getActiveWindow(auction);

      if (activeWindow == -1) return false;
      if (auction.windows[uint256(uint8(activeWindow))].windowType == BidWindowType.OPEN) return false;

      // TODO: gas optimize
      uint256 windowOpen = auction.windows[uint256(uint8(activeWindow))].windowOpenTimestamp;
      uint256 lastBid = auction.bidTimestamp;
      uint256 auctionWouldCloseAt = (windowOpen > lastBid ? windowOpen : lastBid) + auction.windows[uint256(uint8(activeWindow))].timer;

      return block.timestamp <= auctionWouldCloseAt;
    }



    function _getUserPrivateAuctionPermitted() internal pure returns (bool) {
      return true;
    }

    function bid(uint256 _lot) public validAuctionLot(_lot) nonReentrant {
      Auction storage auction = auctions[_lot];

      // VALIDATE: User can participate in auction
      if (auction.isPrivate && !_getUserPrivateAuctionPermitted()) revert PrivateAuction();

      // VALIDATE: Bidding is open
      if (!_getIsBiddingOpen(auction)) revert BiddingClosed();

      auction.bid += bidIncrement;
      auction.bidUser = msg.sender;
      auction.bidTimestamp = block.timestamp;
      
      auction.sum += auction.bid;

      bidPoints = 1e36 / auction.bid;
      auction.points += bidPoints;
      auctionUsers[_lot][msg.sender].points += bidPoints;

      USD.safeTransferFrom(msg.sender, address(this), auction.bid);

      emit Bid(_lot, msg.sender, auction.bid);
    }

    function _finalizeAuction(Auction storage auction) internal {
      // Exit if already finalized
      if (auction.state == AuctionState.FINALIZED) return;

      // Calculate distributions
      uint256 treasuryCut = auction.sum * treasurySplit / 10000;
      uint256 vaultCut = auction.sum - treasuryCut;

      // Add unused vault distribution to treasury
      if (farm == address(0)) {
        treasuryCut += vaultCut;
        vaultCut = 0;
      }

      // Distribute
      if (treasuryCut > 0) {
        USD.safeTransfer(treasury, treasuryCut);
      }
      if (vaultCut > 0) {
        USD.safeTransfer(farm, vaultCut);
        IVaultReceiver(farm).receiveCut(vaultCut);
      }

      // Mark Finalized
      auction.state = AuctionState.FINALIZED;
      emit AuctionFinalized(auction.lot);
    }

    function _claimLotWinnings(Auction storage auction) internal {
      // Exit if claiming not available
      if (msg.sender != auction.bidUser || auction.claimed) return;

      // Winnings to last bidder
      for (uint8 i = 0; i < auction.tokens.length; i++) {
        auction.tokens[i].safeTransfer(auction.bidUser, auction.amounts[i]);
      }

      // Mark Claimed
      auction.claimed = true;
      emit AuctionLotClaimed(auction.lot, msg.sender, auction.tokens, auction.amounts);
    }

    function _claimEmissions(Auction storage auction) internal {
      AuctionUser storage user = auctionUsers[auction.lot][msg.sender];

      // Exit if user already claimed emissions from auction
      if (user.claimed) return;
      
      // Exit early if nothing to claim
      if (user.points == 0) return;

      // Calculate and distribute emissions
      uint256 emissions = (user.points * 1e18) / auction.points;
      GO.safeTransfer(msg.sender, emissions);

      // Mark claimed
      user.claimed = true;
      emit UserClaimedLotEmissions(auction.lot, msg.sender, emissions);
    }

    function claimManyAuctions(uint256[] memory _lots) public nonReentrant {
      for (uint256 i = 0; i < _lots.length; i++) {
        claimAuction(_lots[i]);
      }
    }

    // Claims winnings and any tokens earned during auction
    function claimAuction(uint256 _lot) public validAuctionLot(_lot) nonReentrant {
      Auction storage auction = auctions[_lot];

      if (!_getHasAuctionClosed(auction)) revert BiddingClosed();

      _finalizeAuction(auction);
      _claimLotWinnings(auction);
      _claimEmissions(auction);
    }

    // VIEW

    function getUserAuctionPoints(address _user, uint256 _lot) public view validAuctionLot(_lot) returns (uint256) {
      return auctionUsers[_lot][_user].points;
    }
    function getAuctionTokenEarned(address _user, uint256 _lot) public view validAuctionLot(_lot) returns (uint256) {
      return (auctionUsers[_lot][_user].points * 1e18) / auctions[_lot].points;
    }
    function getAuctionCount() public view returns (uint256) {
      return auctions.length;
    }
    function getAuction (uint256 _lot) public view validAuctionLot(_lot) returns (Auction memory) {
      return auctions[_lot];
    }
    function getEpoch() public view returns (uint256) {
      if (block.timestamp < startTimestamp) return 0;
      return block.timestamp - startTimestamp / epochDuration;
    }
    function getEpochEmission() public view returns (uint256) {
      uint256 epoch = getEpoch();
      if (epoch >= 8) return 0;
      return emissionSharePerEpoch[getEpoch()];
    }
}
