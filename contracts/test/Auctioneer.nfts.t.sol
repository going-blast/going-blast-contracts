// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { Auctioneer } from "../Auctioneer.sol";
import "../IAuctioneer.sol";
import { GOToken } from "../GOToken.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BasicERC20 } from "../BasicERC20.sol";
import { WETH9 } from "../WETH9.sol";
import { AuctionUtils } from "../AuctionUtils.sol";

contract AuctioneerNFTsTest is AuctioneerHelper {
	using SafeERC20 for IERC20;
	using AuctionUtils for Auction;

	function setUp() public override {
		super.setUp();

		farm = new AuctioneerFarm(USD, GO, BID);
		auctioneer.setTreasury(treasury);

		// Distribute GO
		GO.safeTransfer(address(auctioneer), (GO.totalSupply() * 6000) / 10000);
		GO.safeTransfer(presale, (GO.totalSupply() * 2000) / 10000);
		GO.safeTransfer(treasury, (GO.totalSupply() * 1000) / 10000);
		GO.safeTransfer(liquidity, (GO.totalSupply() * 500) / 10000);
		GO.safeTransfer(address(farm), (GO.totalSupply() * 500) / 10000);

		// Initialize after receiving GO token
		auctioneer.initialize(_getNextDay2PMTimestamp());

		// Give WETH to treasury
		vm.deal(treasury, 10e18);

		// Treasury deposit for WETH
		vm.prank(treasury);
		WETH.deposit{ value: 5e18 }();

		// Approve WETH for auctioneer
		vm.prank(treasury);
		IERC20(address(WETH)).approve(address(auctioneer), type(uint256).max);

		// Give usd to users
		USD.mint(user1, 1000e18);
		USD.mint(user2, 1000e18);
		USD.mint(user3, 1000e18);
		USD.mint(user4, 1000e18);

		// Users approve auctioneer
		vm.prank(user1);
		USD.approve(address(auctioneer), 1000e18);
		vm.prank(user2);
		USD.approve(address(auctioneer), 1000e18);
		vm.prank(user3);
		USD.approve(address(auctioneer), 1000e18);
		vm.prank(user4);
		USD.approve(address(auctioneer), 1000e18);
	}

	function _createBaseNFTDailyAuctions() internal {
		// Create auction params
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getNftAuctionParams();

		// Create auction
		auctioneer.createDailyAuctions(params);
	}

	function test_createSingleAuction_WithNFTs() public {
		_createBaseNFTDailyAuctions();

		assertEq(mockNFT1.ownerOf(1), treasury, "Treasury owns NFT1-1");
		assertEq(mockNFT1.ownerOf(2), treasury, "Treasury owns NFT1-2");
		assertEq(mockNFT1.ownerOf(3), address(auctioneer), "Auctioneer owns NFT1-3");
		assertEq(mockNFT1.ownerOf(4), treasury, "Treasury owns NFT1-4");

		assertEq(mockNFT2.ownerOf(1), address(auctioneer), "Auctioneer owns NFT2-1");
		assertEq(mockNFT2.ownerOf(2), treasury, "Treasury owns NFT2-2");
		assertEq(mockNFT2.ownerOf(3), treasury, "Treasury owns NFT2-3");
		assertEq(mockNFT2.ownerOf(4), treasury, "Treasury owns NFT2-4");

		assertEq(auctioneer.getAuction(0).rewards.nfts[0].nft, address(mockNFT1), "Nft 0 added to auction");
		assertEq(auctioneer.getAuction(0).rewards.nfts[1].nft, address(mockNFT2), "Nft 1 added to auction");
		assertEq(auctioneer.getAuction(0).rewards.nfts[0].id, 3, "Nft 0 id added to auction");
		assertEq(auctioneer.getAuction(0).rewards.nfts[1].id, 1, "Nft 1 id added to auction");
	}

	function test_nfts_RevertWhen_TooManyNFTs() public {
		// Create auction params
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getNftAuctionParams();

		// Add NFTs to auction
		params[0].nfts = new NftData[](5);
		params[0].nfts[0] = NftData({ nft: address(mockNFT1), id: 1 });
		params[0].nfts[1] = NftData({ nft: address(mockNFT2), id: 1 });
		params[0].nfts[2] = NftData({ nft: address(mockNFT1), id: 2 });
		params[0].nfts[3] = NftData({ nft: address(mockNFT2), id: 2 });
		params[0].nfts[4] = NftData({ nft: address(mockNFT1), id: 3 });

		// Expect Revert
		vm.expectRevert(TooManyNFTs.selector);

		// Create auction
		auctioneer.createDailyAuctions(params);
	}

	function test_nfts_ReturnedToTreasuryOnCancel() public {
		_createBaseNFTDailyAuctions();

		assertEq(mockNFT1.ownerOf(1), treasury, "Treasury owns NFT1-1");
		assertEq(mockNFT1.ownerOf(2), treasury, "Treasury owns NFT1-2");
		assertEq(mockNFT1.ownerOf(3), address(auctioneer), "Auctioneer owns NFT1-3");
		assertEq(mockNFT1.ownerOf(4), treasury, "Treasury owns NFT1-4");

		assertEq(mockNFT2.ownerOf(1), address(auctioneer), "Auctioneer owns NFT2-1");
		assertEq(mockNFT2.ownerOf(2), treasury, "Treasury owns NFT2-2");
		assertEq(mockNFT2.ownerOf(3), treasury, "Treasury owns NFT2-3");
		assertEq(mockNFT2.ownerOf(4), treasury, "Treasury owns NFT2-4");

		auctioneer.cancelAuction(0, false);

		assertEq(mockNFT1.ownerOf(1), treasury, "Treasury owns NFT1-1");
		assertEq(mockNFT1.ownerOf(2), treasury, "Treasury owns NFT1-2");
		assertEq(mockNFT1.ownerOf(3), treasury, "Treasury owns NFT1-3");
		assertEq(mockNFT1.ownerOf(4), treasury, "Treasury owns NFT1-4");

		assertEq(mockNFT2.ownerOf(1), treasury, "Treasury owns NFT2-1");
		assertEq(mockNFT2.ownerOf(2), treasury, "Treasury owns NFT2-2");
		assertEq(mockNFT2.ownerOf(3), treasury, "Treasury owns NFT2-3");
		assertEq(mockNFT2.ownerOf(4), treasury, "Treasury owns NFT2-4");
	}

	function test_nfts_SentToWinningUserOnClaimLot() public {
		_createBaseNFTDailyAuctions();

		assertEq(mockNFT1.ownerOf(1), treasury, "Treasury owns NFT1-1");
		assertEq(mockNFT1.ownerOf(2), treasury, "Treasury owns NFT1-2");
		assertEq(mockNFT1.ownerOf(3), address(auctioneer), "Auctioneer owns NFT1-3");
		assertEq(mockNFT1.ownerOf(4), treasury, "Treasury owns NFT1-4");

		assertEq(mockNFT2.ownerOf(1), address(auctioneer), "Auctioneer owns NFT2-1");
		assertEq(mockNFT2.ownerOf(2), treasury, "Treasury owns NFT2-2");
		assertEq(mockNFT2.ownerOf(3), treasury, "Treasury owns NFT2-3");
		assertEq(mockNFT2.ownerOf(4), treasury, "Treasury owns NFT2-4");

		// Bid
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);
		_bid(user1);

		// User 1 wins auction
		vm.warp(block.timestamp + 1 days);

		// Claim auction
		vm.prank(user1);
		auctioneer.claimAuctionLot(0, ClaimLotOptions({ paymentType: LotPaymentType.WALLET, unwrapETH: false }));

		assertEq(mockNFT1.ownerOf(1), treasury, "Treasury owns NFT1-1");
		assertEq(mockNFT1.ownerOf(2), treasury, "Treasury owns NFT1-2");
		assertEq(mockNFT1.ownerOf(3), user1, "User1 owns NFT1-3");
		assertEq(mockNFT1.ownerOf(4), treasury, "Treasury owns NFT1-4");

		assertEq(mockNFT2.ownerOf(1), user1, "User1 owns NFT2-1");
		assertEq(mockNFT2.ownerOf(2), treasury, "Treasury owns NFT2-2");
		assertEq(mockNFT2.ownerOf(3), treasury, "Treasury owns NFT2-3");
		assertEq(mockNFT2.ownerOf(4), treasury, "Treasury owns NFT2-4");
	}
}
