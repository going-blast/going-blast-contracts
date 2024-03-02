// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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

interface IPoolReceiver {
  function receiveCut(uint256 _amount) external;
}

contract Auctioneer is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    Auction[] public auctions;
    IERC20 public BID_TOKEN;
    uint256 public BID_INCREMENT;
    uint256 public BID_WINDOW;

    address public TREASURY;
    uint256 public TREASURY_CUT;
    address public POOL;
    uint256 public POOL_CUT;

    error AuctionNotOver();
    error InvalidAuctionId();
    error AlreadyFinalized();
    error AuctionEnded();
    error AuctionNotOpen();
    error NotWinner();
    error NotRecoverable();
    error PermissionDenied();
    error TooSteep();

    event AuctionCreated(uint256 indexed _aid, address indexed _owner);
    event Bid(uint256 indexed _aid, address indexed _user, uint256 _bid);
    event AuctionFinalized(uint256 indexed _aid);
    event AuctionRecovered(uint256 indexed _aid);

    constructor(IERC20 _bidToken, uint256 _bidIncrement, uint256 _bidWindow) Ownable(msg.sender) {
      BID_TOKEN = _bidToken;
      BID_INCREMENT = _bidIncrement;
      BID_WINDOW = _bidWindow;
    }

    function setReceivers(address _treasury, uint256 _treasuryCut, address _pool, uint256 _poolCut) public onlyOwner {
      if (_treasuryCut + _poolCut > 5000) revert TooSteep();

      TREASURY = _treasury;
      TREASURY_CUT = _treasuryCut;

      POOL = _pool;
      POOL_CUT = _poolCut;
    }

    function getAuctionCount() public view returns (uint256) {
      return auctions.length;
    }
    function getAuction (uint256 _aid) public view returns (Auction memory) {
      return auctions[_aid];
    }

    function create(IERC20 _token, uint256 _amount, string memory _name, uint256 _unlockTimestamp) public onlyOwner nonReentrant {
      auctions.push(Auction({
        id: auctions.length,

        owner: msg.sender,
        token: _token,
        amount: _amount,
        name: _name,
        unlockTimestamp: _unlockTimestamp,
        
        sum: 0,
        bid: 0,
        bidTimestamp: block.timestamp,
        bidUser: msg.sender,

        finalized: false
      }));

      emit AuctionCreated(auctions.length, msg.sender);      
    }

    function recover(uint256 _aid) public nonReentrant {
      if (_aid > auctions.length) revert InvalidAuctionId();

      Auction storage auction = auctions[_aid];

      if (auction.bid > 0) revert NotRecoverable();
      if (msg.sender != auction.owner) revert PermissionDenied();

      auction.token.safeTransfer(auction.owner, auction.amount);
      auction.finalized = true;

      emit AuctionRecovered(_aid);
    }

    function bid(uint256 _aid) public {
      if (_aid > auctions.length) revert InvalidAuctionId();

      Auction storage auction = auctions[_aid];

      if (block.timestamp < auction.unlockTimestamp) revert AuctionNotOpen();
      if (auction.finalized || block.timestamp > (auction.bidTimestamp + BID_WINDOW)) revert AuctionEnded();

      auction.bid += BID_INCREMENT;
      auction.bidUser = msg.sender;
      auction.bidTimestamp = block.timestamp;
      
      auction.sum += auction.bid;

      BID_TOKEN.safeTransferFrom(msg.sender, address(this), auction.bid);

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
      uint256 poolCut = POOL == address(0) ? 0 : auction.sum * POOL_CUT / 10000;

      BID_TOKEN.safeTransfer(auction.owner, auction.sum - treasuryCut - poolCut);
      if (treasuryCut > 0) {
        BID_TOKEN.safeTransfer(TREASURY, treasuryCut);
      }
      if (poolCut > 0) {
        BID_TOKEN.safeTransfer(POOL, poolCut);
        IPoolReceiver(POOL).receiveCut(poolCut);
      }

      // Finalize      
      auction.finalized = true;
      emit AuctionFinalized(auction.id);
    }

    function claimWinnings(uint256 _aid) public nonReentrant {
      if (_aid > auctions.length) revert InvalidAuctionId();
      Auction storage auction = auctions[_aid];
      if (msg.sender != auction.bidUser) revert NotWinner();

      _validateAuctionEnded(auction);
      _finalizeAuction(auction);
    }

    function finalizeOnBehalf(uint256 _aid) public nonReentrant {
      // Winner can't just hold auction hostage by not finalizing
      // But this wont be on the frontend, only the explorer

      if (_aid > auctions.length) revert InvalidAuctionId();
      Auction storage auction = auctions[_aid];

      _validateAuctionEnded(auction);
      _finalizeAuction(auction);
    }
}
