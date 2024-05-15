// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AuctionViewUtils } from "../src/AuctionUtils.sol";

contract AuctioneerNFTsTest is AuctioneerHelper {
	using SafeERC20 for IERC20;
	using AuctionViewUtils for Auction;

	function setUp() public override {
		super.setUp();

		auctioneer.updateTreasury(treasury);

		_distributeGO();
		_initializeAuctioneerEmissions();
		_setupAuctioneerTreasury();
		_giveUsersTokensAndApprove();
	}

	function _createBaseNFTDailyAuctions() internal {
		// Create auction params
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getNftAuctionParams();

		// Create auction
		auctioneer.createAuctions(params);
	}

	function test_createSingleAuction_WithNFTs() public {
		_createBaseNFTDailyAuctions();

		assertEq(mockNFT1.ownerOf(1), treasury, "Treasury owns NFT1-1");
		assertEq(mockNFT1.ownerOf(2), treasury, "Treasury owns NFT1-2");
		assertEq(mockNFT1.ownerOf(3), address(auctioneerAuction), "AuctioneerAuction owns NFT1-3");
		assertEq(mockNFT1.ownerOf(4), treasury, "Treasury owns NFT1-4");

		assertEq(mockNFT2.ownerOf(1), address(auctioneerAuction), "AuctioneerAuction owns NFT2-1");
		assertEq(mockNFT2.ownerOf(2), treasury, "Treasury owns NFT2-2");
		assertEq(mockNFT2.ownerOf(3), treasury, "Treasury owns NFT2-3");
		assertEq(mockNFT2.ownerOf(4), treasury, "Treasury owns NFT2-4");

		assertEq(auctioneerAuction.getAuction(0).rewards.nfts[0].nft, address(mockNFT1), "Nft 0 added to auction");
		assertEq(auctioneerAuction.getAuction(0).rewards.nfts[1].nft, address(mockNFT2), "Nft 1 added to auction");
		assertEq(auctioneerAuction.getAuction(0).rewards.nfts[0].id, 3, "Nft 0 id added to auction");
		assertEq(auctioneerAuction.getAuction(0).rewards.nfts[1].id, 1, "Nft 1 id added to auction");
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
		auctioneer.createAuctions(params);
	}

	function test_nfts_ReturnedToTreasuryOnCancel() public {
		_createBaseNFTDailyAuctions();

		assertEq(mockNFT1.ownerOf(1), treasury, "Treasury owns NFT1-1");
		assertEq(mockNFT1.ownerOf(2), treasury, "Treasury owns NFT1-2");
		assertEq(mockNFT1.ownerOf(3), address(auctioneerAuction), "AuctioneerAuction owns NFT1-3");
		assertEq(mockNFT1.ownerOf(4), treasury, "Treasury owns NFT1-4");

		assertEq(mockNFT2.ownerOf(1), address(auctioneerAuction), "AuctioneerAuction owns NFT2-1");
		assertEq(mockNFT2.ownerOf(2), treasury, "Treasury owns NFT2-2");
		assertEq(mockNFT2.ownerOf(3), treasury, "Treasury owns NFT2-3");
		assertEq(mockNFT2.ownerOf(4), treasury, "Treasury owns NFT2-4");

		auctioneer.cancelAuction(0);

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
		assertEq(mockNFT1.ownerOf(3), address(auctioneerAuction), "AuctioneerAuction owns NFT1-3");
		assertEq(mockNFT1.ownerOf(4), treasury, "Treasury owns NFT1-4");

		assertEq(mockNFT2.ownerOf(1), address(auctioneerAuction), "AuctioneerAuction owns NFT2-1");
		assertEq(mockNFT2.ownerOf(2), treasury, "Treasury owns NFT2-2");
		assertEq(mockNFT2.ownerOf(3), treasury, "Treasury owns NFT2-3");
		assertEq(mockNFT2.ownerOf(4), treasury, "Treasury owns NFT2-4");

		// Bid
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);
		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;

		// User 1 wins auction
		vm.warp(block.timestamp + 1 days);

		// Claim auction
		vm.deal(user1, lotPrice);
		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(0, ClaimLotOptions({ paymentType: PaymentType.WALLET }));

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
