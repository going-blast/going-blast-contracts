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


struct BidWindow {
  uint256 duration;
  uint256 window;
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
  bool finalized;
}

struct AuctionParams {
  bool isPrivate;
  uint256 emissionBP; // Emission of this auction of the day's emission (usually 100%)
  IERC20[] tokens;
  uint256 amounts;
  string name;
  BidWindow[] windows;
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

    // EMISSIONS
    IERC20 public GO;
    uint256[8] emissionSharePerEpoch = [128, 64, 32, 16, 8, 4, 2, 1];
    uint256 emissionSharesTotal = 255;
    uint256 emissionPerShare = 255e18;

    uint256 bidPoints; // gas savings to prevent reassignment

    address public treasury;
    address public farm;
    uint256 public treasurySplit = 5000;

    error EmissionTooHigh();
    error AuctionNotOver();
    error InvalidAuctionLot();
    error TooManyTokens();
    error LengthMismatch();
    error NoTokens();
    error AlreadyFinalized();
    error AuctionClosed();
    error AuctionNotOpen();
    error NotWinner();
    error NotCancellable();
    error PermissionDenied();
    error TooSteep();
    error ZeroAddress();
    error PrivateAuction();

    event EmissionOnBidUpdated(uint256 _emissionOnBid);
    event AuctionCreated(uint256 indexed _lot);
    event Bid(uint256 indexed _lot, address indexed _user, uint256 _bid);
    event AuctionFinalized(uint256 indexed _lot);
    event AuctionLotClaimed(uint256 indexed _lot, address indexed _user, address[] _tokens, uint256[] _amounts);
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

    function _getUserPrivateAuctionPermitted() internal view returns (bool) {
      return true;
    }
    modifier privacyFulfilled(uint256 _lot) {
      if (auctions[_lot].isPrivate && !_getUserPrivateAuctionPermitted()) revert PrivateAuction();
      _;
    }
    modifier validAuctionLot(uint256 _lot) {
      if (_lot >= auctions.length) revert InvalidAuctionLot();
      _;
    }
    modifier biddingOpen(uint256 _lot) {
      if (block.timestamp < auctions[_lot].unlockTimestamp) revert AuctionNotOpen();
      if (auctions[_lot].finalized || block.timestamp > (auctions[_lot].bidTimestamp + BID_WINDOW)) revert AuctionClosed();
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

    function create(IERC20[] memory _tokens, uint256[] memory _amounts, string memory _name, uint256 _unlockTimestamp, bool _isPrivate) public onlyOwner nonReentrant {
      if (_tokens.length > 4) revert TooManyTokens();
      if (_tokens.length != _amounts.length) revert LengthMismatch();
      if (_tokens.length == 0) revert NoTokens();

      uint256 lot = auctions.length;
      if (lot == 0) start(_unlockTimestamp);

      // Transfer tokens from treasury
      for (uint8 i = 0; i < _tokens.length; i++) {
        _tokens[i].safeTransferFrom(msg.sender, address(this), _amounts[i]);
      }
      
      auctions.push(Auction({
        lot: auctions.length,
        isPrivate: _isPrivate,
        emission: getEpochEmission(),
        points: 0,

        tokens: _tokens,
        amounts: _amounts,
        name: _name,
        unlockTimestamp: _unlockTimestamp,
        
        sum: 0,
        bid: startingBid,
        bidTimestamp: _unlockTimestamp,
        bidUser: msg.sender,

        claimed: false,
        finalized: false
      }));

      emit AuctionCreated(auctions.length - 1);      
    }

    function cancel(uint256 _lot) public validAuctionLot(_lot) nonReentrant onlyOwner {
      Auction storage auction = auctions[_lot];

      if (auction.bid > startingBid) revert NotCancellable();

      for (uint8 i = 0; i < auction.tokens.length; i++) {
        auction.tokens[i].safeTransfer(treasury, auction.amounts[i]);
      }
      auction.finalized = true;

      emit AuctionCancelled(_lot, msg.sender);
    }

    function biddingWindow(uint256 _lot) public view validAuctionLot(_lot) returns (bool open, uint256 timeRemaining) {
      Auction memory auction = auctions[_lot];

      if (block.timestamp < auction.unlockTimestamp) return (false, 0);
      if (auction.finalized || block.timestamp > (auction.bidTimestamp + BID_WINDOW)) return (false, 0);
      
      open = true;
      timeRemaining = (auction.bidTimestamp + BID_WINDOW) - block.timestamp;
    }

    function bid(uint256 _lot) public validAuctionLot(_lot) privacyFulfilled(_lot) biddingOpen(_lot) nonReentrant {
      Auction storage auction = auctions[_lot];

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

    function _validateAuctionEnded(Auction storage auction) internal view {
      if (block.timestamp <= (auction.bidTimestamp + BID_WINDOW)) revert AuctionNotOver();
    }

    function _finalizeAuction(Auction storage auction) internal {
      // Exit if already finalized
      if (auction.finalized) return;

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
      auction.finalized = true;
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

      _validateAuctionEnded(auction);
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
