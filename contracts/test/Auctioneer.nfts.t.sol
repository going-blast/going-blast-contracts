// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { Auctioneer } from "../Auctioneer.sol";
import "../IAuctioneer.sol";
import { GOToken } from "../GOToken.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BasicERC721 } from "../BasicERC721.sol";
import { BasicERC20 } from "../BasicERC20.sol";
import { WETH9 } from "../WETH9.sol";
import { AuctionUtils } from "../AuctionUtils.sol";

contract AuctioneerNFTsTest is AuctioneerHelper {
	using SafeERC20 for IERC20;
	using AuctionUtils for Auction;

	function setUp() public override {
		super.setUp();

		farm = new AuctioneerFarm();
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

	function test_createSingleAuction_WithNFTs() public {
		// Mint 2 nfts
		BasicERC721 mockNFT1 = new BasicERC721(
			"MOCK_NFT_1",
			"MOCK_NFT_1",
			"https://tokenBaseURI",
			"https://contractURI",
			sender
		);
		mockNFT1.safeMint(treasury);
		vm.prank(treasury);
		mockNFT1.approve(address(auctioneer), 1);
		mockNFT1.safeMint(treasury);
		vm.prank(treasury);
		mockNFT1.approve(address(auctioneer), 2);
		mockNFT1.safeMint(treasury);
		vm.prank(treasury);
		mockNFT1.approve(address(auctioneer), 3);
		mockNFT1.safeMint(treasury);
		vm.prank(treasury);
		mockNFT1.approve(address(auctioneer), 4);

		BasicERC721 mockNFT2 = new BasicERC721(
			"MOCK_NFT_2",
			"MOCK_NFT_2",
			"https://tokenBaseURI",
			"https://contractURI",
			sender
		);
		mockNFT2.safeMint(treasury);
		vm.prank(treasury);
		mockNFT2.approve(address(auctioneer), 1);
		mockNFT2.safeMint(treasury);
		vm.prank(treasury);
		mockNFT2.approve(address(auctioneer), 2);
		mockNFT2.safeMint(treasury);
		vm.prank(treasury);
		mockNFT2.approve(address(auctioneer), 3);
		mockNFT2.safeMint(treasury);
		vm.prank(treasury);
		mockNFT2.approve(address(auctioneer), 4);

		// Create auction params
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		// Add NFTs to auction
		params[0].nfts = new NftData[](2);
		params[0].nfts[0] = NftData({ nft: address(mockNFT1), id: 3 });
		params[0].nfts[1] = NftData({ nft: address(mockNFT2), id: 1 });

		// Create auction
		auctioneer.createDailyAuctions(params);

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

	// TODO: Ensure nfts returned if auction cancelled
	// TODO: validate that nfts and nftIds have same length
	// TODO: validate that user receives NFTs when claiming lot
}
