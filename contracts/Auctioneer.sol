// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import { GavelToken } from "./GavelToken.sol";
import "./IVaultReceiver.sol";
import "./IAuctioneer.sol";
import "./AuctionUtils.sol";



contract Auctioneer is Ownable, ReentrancyGuard, IAuctioneer {
    using SafeERC20 for IERC20;
    using AuctionUtils for Auction;
    using AuctionParamsUtils for AuctionParams;

    // CORE
    uint256 public lotCount;
    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => mapping(uint8 => BidWindow)) public auctionBidWindows;
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


    constructor(IERC20 _usd, uint256 _bidIncrement, uint256 _startingBid, uint256 _privateRequirement) Ownable(msg.sender) {
      USD = _usd;
      bidIncrement = _bidIncrement;
      startingBid = _startingBid;
      privateAuctionRequirement = _privateRequirement;
    }

    modifier validAuctionLot(uint256 _lot) {
      if (_lot >= lotCount) revert InvalidAuctionLot();
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

    function _createSingleAuction(AuctionParams memory _params) internal {
      _params.validateUnlock();
      _params.validateTokens();
      _params.validateBidWindows();
      
      uint256 lot = lotCount;
      if (lot == 0) start(_params.unlockTimestamp);

      // Transfer tokens from treasury
      for (uint8 i = 0; i < _params.tokens.length; i++) {
        _params.tokens[i].safeTransferFrom(treasury, address(this), _params.amounts[i]);
      }

      auctions[lot].lot = lot;
      auctions[lot].isPrivate = _params.isPrivate;
      auctions[lot].emission = _getEmissionForAuction(_params.emissionBP);
      auctions[lot].addBidWindows(_params, onceTwiceBlastBonusTime);
      // auctions[lot].points = 0;

      auctions[lot].tokens = _params.tokens;
      auctions[lot].amounts = _params.amounts;
      auctions[lot].name = _params.name;
      auctions[lot].unlockTimestamp = _params.unlockTimestamp;
        
      // auctions[lot].sum = 0;
      auctions[lot].bid = startingBid;
      auctions[lot].bidTimestamp = _params.unlockTimestamp;
      auctions[lot].bidUser = msg.sender;

      // auctions[lot].claimed = false;
      // auctions[lot].finalized = false;


      lotCount++;
      emit AuctionCreated(lot);      
    }

    function cancel(uint256 _lot) public validAuctionLot(_lot) nonReentrant onlyOwner {
      Auction storage auction = auctions[_lot];

      if (auction.bid > startingBid) revert NotCancellable();

      for (uint8 i = 0; i < auction.tokens.length; i++) {
        auction.tokens[i].safeTransfer(treasury, auction.amounts[i]);
      }

      auction.finalize();

      emit AuctionCancelled(_lot, msg.sender);
    }




    function _getUserPrivateAuctionPermitted() internal pure returns (bool) {
      return true;
    }

    function bid(uint256 _lot) public validAuctionLot(_lot) nonReentrant {
      Auction storage auction = auctions[_lot];
      auction.validateBiddingOpen();

      // VALIDATE: User can participate in auction
      if (auction.isPrivate && !_getUserPrivateAuctionPermitted()) revert PrivateAuction();

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
      uint256 emissions = auction.emission * (user.points * 1e18) / auction.points;
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

    function claimAuction(uint256 _lot) public validAuctionLot(_lot) nonReentrant {
      Auction storage auction = auctions[_lot];

      auction.validateEnded();

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
