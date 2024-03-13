// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { Auctioneer } from "../Auctioneer.sol";
import "../IAuctioneer.sol";
import { GOToken } from "../GOToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AuctioneerFarm } from "../AuctioneerFarm.sol";
import { BasicERC20 } from "../BasicERC20.sol";
import { BasicERC721 } from "../BasicERC721.sol";
import { IWETH, WETH9 } from "../WETH9.sol";
import { AuctioneerHarness } from "./AuctioneerHarness.sol";

abstract contract AuctioneerHelper is AuctioneerEvents, Test {
	// DATA

	address public deployer = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
	address public sender = 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496;
	address public dead = 0x000000000000000000000000000000000000dEaD;

	address public presale = address(30);

	address public liquidity = address(40);

	address public treasury = address(50);
	address public treasury2 = address(51);

	address public user1 = address(100);
	address public user2 = address(101);
	address public user3 = address(102);
	address public user4 = address(103);

	AuctioneerHarness public auctioneer;
	AuctioneerFarm public farm;
	BasicERC20 public USD;
	IWETH public WETH;
	address public ETH_ADDR = address(0);
	BasicERC20 public XXToken;
	BasicERC20 public YYToken;
	BasicERC721 public mockNFT1;
	BasicERC721 public mockNFT2;
	IERC20 public GO;

	// SETUP

	function setUp() public virtual {
		USD = new BasicERC20("USD", "USD");
		WETH = IWETH(address(new WETH9()));
		GO = new GOToken(deployer);
		XXToken = new BasicERC20("XX", "XX");
		YYToken = new BasicERC20("YY", "YY");

		auctioneer = new AuctioneerHarness(USD, GO, WETH, 1e18, 1e16, 1e18, 20e18);
		farm = new AuctioneerFarm();

		// Create NFTs
		mockNFT1 = new BasicERC721("MOCK_NFT_1", "MOCK_NFT_1", "https://tokenBaseURI", "https://contractURI", sender);
		mockNFT2 = new BasicERC721("MOCK_NFT_2", "MOCK_NFT_2", "https://tokenBaseURI", "https://contractURI", sender);

		// Mint nft1
		mockNFT1.safeMint(treasury);
		mockNFT1.safeMint(treasury);
		mockNFT1.safeMint(treasury);
		mockNFT1.safeMint(treasury);

		// Mint nft2
		mockNFT2.safeMint(treasury);
		mockNFT2.safeMint(treasury);
		mockNFT2.safeMint(treasury);
		mockNFT2.safeMint(treasury);

		// Approve nft1
		vm.prank(treasury);
		mockNFT1.approve(address(auctioneer), 1);
		vm.prank(treasury);
		mockNFT1.approve(address(auctioneer), 2);
		vm.prank(treasury);
		mockNFT1.approve(address(auctioneer), 3);
		vm.prank(treasury);
		mockNFT1.approve(address(auctioneer), 4);

		// Approve nft2
		vm.prank(treasury);
		mockNFT2.approve(address(auctioneer), 1);
		vm.prank(treasury);
		mockNFT2.approve(address(auctioneer), 2);
		vm.prank(treasury);
		mockNFT2.approve(address(auctioneer), 3);
		vm.prank(treasury);
		mockNFT2.approve(address(auctioneer), 4);
	}

	// UTILS

	function _getNextDay2PMTimestamp() public view returns (uint256) {
		return (block.timestamp / 1 days) * 1 days + 14 hours;
	}
	function _getDayInFuture2PMTimestamp(uint256 daysInFuture) public view returns (uint256) {
		return ((block.timestamp / 1 days) + daysInFuture) * 1 days + 14 hours;
	}

	function _getBaseSingleAuctionParams() public view returns (AuctionParams memory params) {
		TokenData[] memory tokens = new TokenData[](1);
		tokens[0] = TokenData({ token: ETH_ADDR, amount: 1e18 });

		BidWindowParams[] memory windows = new BidWindowParams[](3);
		windows[0] = BidWindowParams({ windowType: BidWindowType.OPEN, duration: 6 hours, timer: 0 });
		windows[1] = BidWindowParams({ windowType: BidWindowType.TIMED, duration: 2 hours, timer: 2 minutes });
		windows[2] = BidWindowParams({ windowType: BidWindowType.INFINITE, duration: 0, timer: 1 minutes });

		params = AuctionParams({
			isPrivate: false,
			lotValue: 4000e18,
			emissionBP: 10000,
			tokens: tokens,
			nfts: new NftData[](0),
			name: "Single Token Auction",
			windows: windows,
			unlockTimestamp: _getNextDay2PMTimestamp()
		});
	}

	function _getNftAuctionParams() public view returns (AuctionParams memory params) {
		params = _getBaseSingleAuctionParams();

		// Add NFTs to auction
		params.nfts = new NftData[](2);
		params.nfts[0] = NftData({ nft: address(mockNFT1), id: 3 });
		params.nfts[1] = NftData({ nft: address(mockNFT2), id: 1 });
	}

	function _getMultiTokenSingleAuctionParams() public view returns (AuctionParams memory params) {
		TokenData[] memory tokens = new TokenData[](3);
		tokens[0] = TokenData({ token: ETH_ADDR, amount: 1e18 });
		tokens[1] = TokenData({ token: address(XXToken), amount: 100e18 });
		tokens[2] = TokenData({ token: address(YYToken), amount: 50e18 });

		BidWindowParams[] memory windows = new BidWindowParams[](3);
		windows[0] = BidWindowParams({ windowType: BidWindowType.OPEN, duration: 6 hours, timer: 0 });
		windows[1] = BidWindowParams({ windowType: BidWindowType.TIMED, duration: 2 hours, timer: 2 minutes });
		windows[2] = BidWindowParams({ windowType: BidWindowType.INFINITE, duration: 0, timer: 1 minutes });

		params = AuctionParams({
			isPrivate: false,
			lotValue: 6000e18,
			emissionBP: 10000,
			tokens: tokens,
			nfts: new NftData[](0),
			name: "Multi Token Auction",
			windows: windows,
			unlockTimestamp: _getNextDay2PMTimestamp()
		});
	}

	function _createBaseAuctionOnDay(uint256 daysInFuture) internal {
		uint256 unlockTimestamp = _getDayInFuture2PMTimestamp(daysInFuture);

		AuctionParams[] memory params = new AuctionParams[](1);
		// Create single token auction
		params[0] = _getBaseSingleAuctionParams();
		params[0].unlockTimestamp = unlockTimestamp;

		// Create single token + nfts auction
		auctioneer.createDailyAuctions(params);
	}

	// EVENTS

	error OwnableUnauthorizedAccount(address account);
	error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
	error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

	// BIDS

	function _bidShouldRevert(address user) public {
		vm.expectRevert(BiddingClosed.selector);
		_bid(user);
	}
	function _bidShouldEmit(address user) public {
		uint256 expectedBid = auctioneer.getAuction(0).bidData.bid + auctioneer.bidIncrement();
		vm.expectEmit(true, true, true, true);
		emit Bid(0, user, 1, expectedBid, "");
		_bid(user);
	}
	function _bid(address user) public {
		vm.prank(user);
		auctioneer.bid(0, 1, true);
	}
	function _bidOnLot(address user, uint256 lot) public {
		vm.prank(user);
		auctioneer.bid(lot, 1, true);
	}
	function _multibid(address user, uint256 bidCount) public {
		vm.prank(user);
		auctioneer.bid(0, bidCount, true);
	}
	function _multibidLot(address user, uint256 bidCount, uint256 lot) public {
		vm.prank(user);
		auctioneer.bid(lot, bidCount, true);
	}
	function _bidUntil(address user, uint256 timer, uint256 until) public {
		while (true) {
			if (block.timestamp > until) return;
			vm.warp(block.timestamp + timer);
			_bid(user);
		}
	}
}
