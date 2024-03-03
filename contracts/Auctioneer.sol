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

struct Auction {
  uint256 id;

  address owner;
  IERC20 token;
  uint256 amount;
  string name;
  uint256 unlockTimestamp;
  
  uint256 sum;
  uint256 bid;
  uint256 bidTimestamp;
  address bidUser;

  bool finalized;
}

contract Auctioneer is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    Auction[] public auctions;
    IERC20 public BID_TOKEN;
    uint256 public BID_INCREMENT;
    uint256 public BID_WINDOW;
    uint256 public STARTING_BID;
    uint256 public GAVEL_EMISSION_ON_BID;
    GavelToken public GAVEL_TOKEN;

    address public TREASURY;
    uint256 public TREASURY_CUT;
    address public VAULT;
    uint256 public VAULT_CUT;

    error EmissionTooHigh();
    error AuctionNotOver();
    error InvalidAuctionId();
    error AlreadyFinalized();
    error AuctionClosed();
    error AuctionNotOpen();
    error NotWinner();
    error NotCancellable();
    error PermissionDenied();
    error TooSteep();
    error ZeroAddress();

    event EmissionOnBidUpdated(uint256 _emissionOnBid);
    event AuctionCreated(uint256 indexed _aid, address indexed _owner);
    event Bid(uint256 indexed _aid, address indexed _user, uint256 _bid);
    event AuctionFinalized(uint256 indexed _aid);
    event AuctionCancelled(uint256 indexed _aid, address indexed _owner);

    constructor(IERC20 _bidToken, uint256 _bidIncrement, uint256 _bidWindow, uint256 _startingBid) Ownable(msg.sender) {
      BID_TOKEN = _bidToken;
      BID_INCREMENT = _bidIncrement;
      BID_WINDOW = _bidWindow;
      STARTING_BID = _startingBid;
    }

    modifier validAuctionId(uint256 _aid) {
      if (_aid >= auctions.length) revert InvalidAuctionId();
      _;
    }
    modifier biddingOpen(uint256 _aid) {
      if (block.timestamp < auctions[_aid].unlockTimestamp) revert AuctionNotOpen();
      if (auctions[_aid].finalized || block.timestamp > (auctions[_aid].bidTimestamp + BID_WINDOW)) revert AuctionClosed();
      _;
    }

    function setGavelEmissionOnBid(uint256 _emissionOnBid) public onlyOwner {
      if (_emissionOnBid > 20000) revert EmissionTooHigh();
      GAVEL_EMISSION_ON_BID = _emissionOnBid;
      emit EmissionOnBidUpdated(_emissionOnBid);
    }

    function setReceivers(address _treasury, uint256 _treasuryCut, address _vault, uint256 _vaultCut) public onlyOwner {
      if (_treasuryCut + _vaultCut > 5000) revert TooSteep();
      if (_treasury == address(0) && _treasuryCut > 0) revert ZeroAddress();
      if (_vault == address(0) && _vaultCut > 0) revert ZeroAddress();


      TREASURY = _treasury;
      TREASURY_CUT = _treasuryCut;

      VAULT = _vault;
      VAULT_CUT = _vaultCut;
    }

    function getAuctionCount() public view returns (uint256) {
      return auctions.length;
    }
    function getAuction (uint256 _aid) public view validAuctionId(_aid) returns (Auction memory) {
      return auctions[_aid];
    }

    function create(IERC20 _token, uint256 _amount, string memory _name, uint256 _unlockTimestamp) public onlyOwner nonReentrant {
      _token.safeTransferFrom(msg.sender, address(this), _amount);
      
      auctions.push(Auction({
        id: auctions.length,

        owner: msg.sender,
        token: _token,
        amount: _amount,
        name: _name,
        unlockTimestamp: _unlockTimestamp,
        
        sum: 0,
        bid: STARTING_BID,
        bidTimestamp: _unlockTimestamp,
        bidUser: msg.sender,

        finalized: false
      }));

      emit AuctionCreated(auctions.length - 1, msg.sender);      
    }

    function cancel(uint256 _aid) public validAuctionId(_aid) nonReentrant {
      Auction storage auction = auctions[_aid];

      if (auction.bid > STARTING_BID) revert NotCancellable();
      if (msg.sender != auction.owner) revert PermissionDenied();

      auction.token.safeTransfer(auction.owner, auction.amount);
      auction.finalized = true;

      emit AuctionCancelled(_aid, msg.sender);
    }

    function biddingWindow(uint256 _aid) public view validAuctionId(_aid) returns (bool open, uint256 timeRemaining) {
      Auction memory auction = auctions[_aid];

      if (block.timestamp < auction.unlockTimestamp) return (false, 0);
      if (auction.finalized || block.timestamp > (auction.bidTimestamp + BID_WINDOW)) return (false, 0);
      
      open = true;
      timeRemaining = (auction.bidTimestamp + BID_WINDOW) - block.timestamp;
    }

    function bid(uint256 _aid) public validAuctionId(_aid) biddingOpen(_aid) nonReentrant {
      Auction storage auction = auctions[_aid];

      auction.bid += BID_INCREMENT;
      auction.bidUser = msg.sender;
      auction.bidTimestamp = block.timestamp;
      
      auction.sum += auction.bid;

      BID_TOKEN.safeTransferFrom(msg.sender, address(this), auction.bid);
      GAVEL_TOKEN.mint(msg.sender, (GAVEL_EMISSION_ON_BID  * 1e18) / 10000);

      emit Bid(_aid, msg.sender, auction.bid);
    }

    function _validateAuctionEnded(Auction storage auction) internal view {
      if (auction.finalized) revert AlreadyFinalized();
      if (block.timestamp <= (auction.bidTimestamp + BID_WINDOW)) revert AuctionNotOver();
    }

    function _finalizeAuction(Auction storage auction) internal {
      // Winnings to last bidder
      auction.token.safeTransfer(auction.bidUser, auction.amount);

      // Distribute bids
      uint256 treasuryCut = TREASURY == address(0) ? 0 : auction.sum * TREASURY_CUT / 10000;
      uint256 vaultCut = VAULT == address(0) ? 0 : auction.sum * VAULT_CUT / 10000;

      BID_TOKEN.safeTransfer(auction.owner, auction.sum - treasuryCut - vaultCut);
      if (treasuryCut > 0) {
        BID_TOKEN.safeTransfer(TREASURY, treasuryCut);
      }
      if (vaultCut > 0) {
        BID_TOKEN.safeTransfer(VAULT, vaultCut);
        IVaultReceiver(VAULT).receiveCut(vaultCut);
      }

      // Finalize      
      auction.finalized = true;
      emit AuctionFinalized(auction.id);
    }

    function claimWinnings(uint256 _aid) public validAuctionId(_aid) nonReentrant {
      Auction storage auction = auctions[_aid];
      if (msg.sender != auction.bidUser) revert NotWinner();

      _validateAuctionEnded(auction);
      _finalizeAuction(auction);
    }

    function finalizeOnBehalf(uint256 _aid) public validAuctionId(_aid) nonReentrant {
      // Winner can't just hold auction hostage by not finalizing
      // But this wont be on the frontend, only the explorer

      Auction storage auction = auctions[_aid];

      _validateAuctionEnded(auction);
      _finalizeAuction(auction);
    }
}
