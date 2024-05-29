// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/IAuctioneerFarm.sol";

contract AuctioneerRunesTest is AuctioneerHelper, AuctioneerFarmEvents {
	using SafeERC20 for IERC20;

	function setUp() public override {
		super.setUp();

		_distributeGO();
		_initializeAuctioneerEmissions();
		_setupAuctioneerTreasury();
		_giveUsersTokensAndApprove();
		_auctioneerUpdateFarm();
		_initializeFarmEmissions();
		_initializeFarmVoucherEmissions();
		_createDefaultDay1Auction();
	}

	function _farmDeposit(address payable user, uint256 pid, uint256 amount) public {
		vm.prank(user);
		farm.deposit(pid, amount, user);
	}
	function _farmWithdraw(address payable user, uint256 pid, uint256 amount) public {
		vm.prank(user);
		farm.withdraw(pid, amount, user);
	}

	uint256 public user1Deposited = 5e18;
	uint256 public user2Deposited = 15e18;
	uint256 public user3Deposited = 0.75e18;
	uint256 public user4Deposited = 2.8e18;
	uint256 public totalDeposited = user1Deposited + user2Deposited + user3Deposited + user4Deposited;

	// OPTIONS

	function test_runicLastBidderBonus_RevertWhen_Invalid() public {
		vm.expectRevert(Invalid.selector);
		auctioneerAuction.updateRunicLastBidderBonus(5001);
	}

	function test_runicLastBidderBonus_ExpectEmit_UpdatedRunicLastBidderBonus() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedRunicLastBidderBonus(0);

		auctioneerAuction.updateRunicLastBidderBonus(0);
	}

	function test_runicLastBidderBonus_Expect_Updated() public {
		assertEq(auctioneerAuction.runicLastBidderBonus(), 2000, "Initial bonus set to 2000");

		auctioneerAuction.updateRunicLastBidderBonus(1000);

		assertEq(auctioneerAuction.runicLastBidderBonus(), 1000, "Bonus updated to 1000");
	}

	// CREATE

	function test_runes_create_RevertWhen_InvalidNumberOfRuneSymbols() public {
		AuctionParams[] memory params = new AuctionParams[](1);

		// RevertWhen 1 rune
		params[0] = _getRunesAuctionParams(1);
		vm.expectRevert(InvalidRunesCount.selector);
		auctioneer.createAuctions(params);

		// RevertWhen 8 rune
		params[0] = _getRunesAuctionParams(6);
		vm.expectRevert(InvalidRunesCount.selector);
		auctioneer.createAuctions(params);
	}

	function test_runes_create_RevertWhen_DuplicateRuneSymbols() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getRunesAuctionParams(2);
		params[0].runeSymbols[0] = 2;
		params[0].runeSymbols[1] = 2;

		vm.expectRevert(DuplicateRuneSymbols.selector);
		auctioneer.createAuctions(params);
	}

	function test_runes_create_RevertWhen_RuneSymbol0Used() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getRunesAuctionParams(2);
		params[0].runeSymbols[0] = 0;

		vm.expectRevert(InvalidRuneSymbol.selector);
		auctioneer.createAuctions(params);
	}

	function test_runes_create_RevertWhen_NFTsWithRunes() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		// Add NFTs to auction
		params[0].nfts = new NftData[](2);
		params[0].nfts[0] = NftData({ nft: address(mockNFT1), id: 3 });
		params[0].nfts[1] = NftData({ nft: address(mockNFT2), id: 1 });

		// Add RUNEs to auction
		uint8 numberOfRunes = 3;
		params[0].runeSymbols = new uint8[](numberOfRunes);
		for (uint8 i = 0; i < numberOfRunes; i++) {
			params[0].runeSymbols[i] = i;
		}

		vm.expectRevert(CannotHaveNFTsWithRunes.selector);
		auctioneer.createAuctions(params);
	}

	function test_runes_create_0RunesParams_NoRunesAddedToAuction() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createAuctions(params);

		uint256 lot = auctioneerAuction.lotCount() - 1;

		assertEq(auctioneerAuction.getAuction(lot).runes.length, 0, "Auction should not have any runes");
		assertEq(auctioneerAuction.exposed_auction_hasRunes(lot), false, "Auction should not return true from .hasRunes");
	}

	function test_runes_create_3RunesParams_4RunesInAuction() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getRunesAuctionParams(3);
		auctioneer.createAuctions(params);

		uint256 lot = auctioneerAuction.lotCount() - 1;

		assertEq(auctioneerAuction.getAuction(lot).runes.length, 4, "Auction should have 4 runes (1 empty + 3 real)");
		assertEq(auctioneerAuction.exposed_auction_hasRunes(lot), true, "Auction should return true from .hasRunes");
	}

	function test_runes_create_5RunesParams_6RunesInAuction() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getRunesAuctionParams(5);
		auctioneer.createAuctions(params);

		uint256 lot = auctioneerAuction.lotCount() - 1;

		assertEq(auctioneerAuction.getAuction(lot).runes.length, 6, "Auction should have 6 runes (1 empty + 5 real)");
		assertEq(auctioneerAuction.exposed_auction_hasRunes(lot), true, "Auction should return true from .hasRunes");
	}

	function test_runes_create_RuneSymbolsAddedCorrectly() public {
		AuctionParams[] memory params = new AuctionParams[](1);

		uint8 numberOfRunes = 5;
		params[0] = _getRunesAuctionParams(numberOfRunes);
		params[0].runeSymbols[0] = 4;
		params[0].runeSymbols[1] = 1;
		params[0].runeSymbols[2] = 3;
		params[0].runeSymbols[3] = 10;
		params[0].runeSymbols[4] = 7;
		auctioneer.createAuctions(params);

		uint256 lot = auctioneerAuction.lotCount() - 1;

		BidRune[] memory auctionRunes = auctioneerAuction.getAuction(lot).runes;

		for (uint8 i = 0; i <= numberOfRunes; i++) {
			assertEq(auctionRunes[i].bids, 0, "Initialized with 0 bids");
			if (i == 0) assertEq(auctionRunes[i].runeSymbol, 0, "First rune should have empty rune symbol");
			else assertEq(auctionRunes[i].runeSymbol, params[0].runeSymbols[i - 1], "Rune symbol should match");
		}
	}

	// BID

	function _innerTest_runesAgainstLot(uint8 numRunes) public {
		uint256 lot = _createDailyAuctionWithRunes(numRunes, true);

		uint256 snapshot = vm.snapshot();

		// 2 runes lot
		for (uint8 i = 0; i < 10; i++) {
			vm.revertTo(snapshot);

			bool validRune = true;
			if (numRunes == 0 && i != 0) validRune = false;
			if (numRunes > 0 && (i == 0 || i > numRunes)) validRune = false;
			// console.log("    Test rune: %s, expected to: %s", i, validRune ? "EMIT" : "REVERT");

			if (validRune) {
				_expectEmitAuctionEvent_Bid(lot, user1, "", i, 1);
			} else {
				vm.expectRevert(InvalidRune.selector);
			}
			_bidWithRune(user1, lot, i);
		}
	}

	function test_runes_bid_RevertWhen_InvalidRune() public {
		uint256 snapshot = vm.snapshot();

		uint8[5] memory numRunesPerTest = [0, 2, 3, 4, 5];

		for (uint8 i = 0; i < numRunesPerTest.length; i++) {
			vm.revertTo(snapshot);
			_innerTest_runesAgainstLot(numRunesPerTest[i]);
		}
	}

	function test_runes_bid_Expect_BidsAreAddedToRuneBids() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		assertEq(auctioneerAuction.getAuction(lot).runes[1].bids, 0, "Rune 1 has 0 bids");
		_bidWithRune(user1, lot, 1);
		assertEq(auctioneerAuction.getAuction(lot).runes[1].bids, 1, "Rune 1 has 1 bid");
		_bidWithRune(user1, lot, 1);
		assertEq(auctioneerAuction.getAuction(lot).runes[1].bids, 2, "Rune 1 has 2 bids");
	}

	function test_runes_bid_Expect_AuctionBidRuneSetCorrectly() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		assertEq(auctioneerAuction.getAuction(lot).bidData.bidRune, 0, "No rune has been bid on yet");

		_bidWithRune(user1, lot, 1);
		assertEq(auctioneerAuction.getAuction(lot).bidData.bidRune, 1, "Rune 1 is currently winning rune");

		_bidWithRune(user2, lot, 2);
		assertEq(auctioneerAuction.getAuction(lot).bidData.bidRune, 2, "Rune 2 is currently winning rune");
	}

	// CLAIMING

	function test_runes_win_RevertWhen_NotWinningRune() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		_bidWithRune(user1, lot, 1);
		_bidWithRune(user2, lot, 2);

		vm.warp(block.timestamp + 1 days);

		assertEq(auctioneerAuction.exposed_auction_isEnded(lot), true, "Auction has ended");
		assertEq(auctioneerAuction.getAuction(lot).bidData.bidRune, 2, "Rune 2 has won");
		uint256 lotPrice = auctioneerAuction.getAuction(lot).bidData.bid;
		vm.deal(user1, lotPrice);
		vm.deal(user2, lotPrice);

		vm.expectRevert(NotWinner.selector);

		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(lot, "");

		_expectEmitAuctionEvent_Claim(lot, user2, "USER2 CLAIM");

		vm.prank(user2);
		auctioneer.claimLot{ value: lotPrice }(lot, "USER2 CLAIM");
	}

	function test_runes_win_Expect_lotClaimedSetToTrue() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		_bidWithRune(user1, lot, 1);
		_bidWithRune(user2, lot, 2);

		uint256 lotPrice = auctioneerAuction.getAuction(lot).bidData.bid;
		vm.deal(user2, lotPrice);

		vm.warp(block.timestamp + 1 days);

		vm.prank(user2);
		auctioneer.claimLot{ value: lotPrice }(lot, "");

		assertEq(auctioneer.getAuctionUser(lot, user2).lotClaimed, true, "User has claimed lot");
	}
	function test_runes_win_RevertWhen_AlreadyClaimed() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		_bidWithRune(user1, lot, 1);
		_bidWithRune(user2, lot, 2);

		uint256 lotPrice = auctioneerAuction.getAuction(lot).bidData.bid;
		vm.deal(user1, lotPrice);
		vm.deal(user2, lotPrice);

		vm.warp(block.timestamp + 1 days);

		vm.prank(user2);
		auctioneer.claimLot{ value: lotPrice }(lot, "");

		assertEq(auctioneer.getAuctionUser(lot, user2).lotClaimed, true, "User has claimed lot");

		vm.expectRevert(UserAlreadyClaimedLot.selector);

		vm.prank(user2);
		auctioneer.claimLot{ value: lotPrice }(lot, "");
	}

	function test_runes_win_Expect_0RunesUserShare100Perc() public {
		uint256 lot = _createDailyAuctionWithRunes(0, true);

		_bidWithRune(user1, lot, 0);
		_bidWithRune(user2, lot, 0);

		vm.warp(block.timestamp + 1 days);

		uint256 auctionETH = 1e18;
		uint256 revenue = auctioneerAuction.getAuction(lot).bidData.revenue;
		uint256 lotPrice = auctioneerAuction.getAuction(lot).bidData.bid;
		vm.deal(user2, lotPrice);

		_prepExpectETHBalChange(0, user2);
		_prepExpectETHBalChange(0, treasury);
		_prepExpectETHBalChange(0, address(auctioneerAuction));

		vm.prank(user2);
		auctioneer.claimLot{ value: lotPrice }(lot, "");

		_expectETHBalChange(
			0,
			user2,
			(-1 * int256(lotPrice)) + int256(auctionETH),
			"User 3. Decrease by lot price, increase by prize"
		);
		_expectETHBalChange(
			0,
			treasury,
			int256(lotPrice) + int256(revenue),
			"Treasury. Increase by lot price (claim) and revenue (finalize)"
		);
		_expectETHBalChange(
			0,
			address(auctioneerAuction),
			int256(auctionETH) * -1,
			"AuctioneerAuction. Decrease by prize amount"
		);
	}

	function test_runes_win_Expect_2RunesUserShareSplit() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		uint256 user1Bids = 86;
		uint256 user2Bids = 6;
		uint256 user3Bids = 37;
		uint256 user4Bids = 123;

		_multibidWithRune(user1, lot, user1Bids, 1);
		_multibidWithRune(user2, lot, user2Bids, 1);
		_multibidWithRune(user3, lot, user3Bids, 2);
		_multibidWithRune(user4, lot, user4Bids, 2);

		vm.warp(block.timestamp + 1 days);

		uint256 auctionETH = 1e18;

		// Finalize auction
		auctioneer.finalizeAuction(lot);

		{
			// USER 3
			UserLotInfo memory user3LotInfo = getUserLotInfo(lot, user3);
			vm.deal(user3, user3LotInfo.price);
			uint256 user3Prize = (auctionETH * user3LotInfo.shareOfLot) / 1e18;

			_prepExpectETHBalChange(0, user3);
			_prepExpectETHBalChange(0, address(auctioneer));
			_prepExpectETHBalChange(0, treasury);

			vm.prank(user3);
			auctioneer.claimLot{ value: user3LotInfo.price }(lot, "");

			// Should go from user3 -> auctioneer -> treasury
			_expectETHBalChange(
				0,
				user3,
				(-1 * int256(user3LotInfo.price)) + int256(user3Prize),
				"User 3. Increase by prize, decrease by price"
			);
			_expectETHBalChange(0, address(auctioneer), int256(0), "Auctioneer");
			_expectETHBalChange(0, treasury, int256(user3LotInfo.price), "Treasury");
		}

		{
			// USER 4
			UserLotInfo memory user4LotInfo = getUserLotInfo(lot, user4);
			vm.deal(user4, user4LotInfo.price);
			uint256 user4Prize = (auctionETH * user4LotInfo.shareOfLot) / 1e18;

			_prepExpectETHBalChange(1, user4);
			_prepExpectETHBalChange(1, address(auctioneer));
			_prepExpectETHBalChange(1, treasury);

			vm.prank(user4);
			auctioneer.claimLot{ value: user4LotInfo.price }(lot, "");

			// Should go from user4 -> auctioneer -> treasury
			_expectETHBalChange(
				1,
				user4,
				(-1 * int256(user4LotInfo.price)) + int256(user4Prize),
				"User 4. Increase by prize, decrease by price"
			);
			_expectETHBalChange(1, address(auctioneer), int256(0), "Auctioneer");
			_expectETHBalChange(1, treasury, int256(user4LotInfo.price), "Treasury");
		}
	}

	function test_runes_LastBidderBonus() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);
		uint256 runicLastBidderBonus = auctioneerAuction.runicLastBidderBonus();

		uint256 userBids = 100;
		uint256 totalBids = 400;
		uint256 bonusBids = (totalBids * runicLastBidderBonus) / 10000;
		uint256 totalBidsWithBonus = (totalBids * (10000 + runicLastBidderBonus)) / 10000;
		uint256 expectedNonLastBidderShare = (userBids * 1e18) / totalBidsWithBonus;
		uint256 expectedLastBidderShare = ((userBids + bonusBids) * 1e18) / totalBidsWithBonus;

		console.log("Bids %s, bonus bids %s, bids with bonus %s", totalBids, bonusBids, totalBidsWithBonus);
		console.log("NonLast share %s, last share %s", expectedNonLastBidderShare, expectedLastBidderShare);

		_multibidWithRune(user1, lot, userBids, 1);
		_multibidWithRune(user2, lot, userBids, 1);
		_multibidWithRune(user3, lot, userBids, 1);
		_multibidWithRune(user4, lot, userBids, 1);

		_warpToAuctionEndTimestamp(lot);

		// SHARES
		{
			uint256 user1ShareOfLot = getUserLotInfo(lot, user1).shareOfLot;
			uint256 user2ShareOfLot = getUserLotInfo(lot, user2).shareOfLot;
			uint256 user3ShareOfLot = getUserLotInfo(lot, user3).shareOfLot;
			uint256 user4ShareOfLot = getUserLotInfo(lot, user4).shareOfLot;

			assertEq(expectedNonLastBidderShare, user1ShareOfLot, "User1 share should not have bonus");
			assertEq(expectedNonLastBidderShare, user2ShareOfLot, "User2 share should not have bonus");
			assertEq(expectedNonLastBidderShare, user3ShareOfLot, "User3 share should not have bonus");
			assertEq(expectedLastBidderShare, user4ShareOfLot, "User4 share should have bonus");

			assertApproxEqAbs(
				user1ShareOfLot + user2ShareOfLot + user3ShareOfLot + user4ShareOfLot,
				1e18,
				10,
				"Shares should add up to 1e18"
			);
		}

		// PRICES
		{
			uint256 lotPrice = auctioneerAuction.getAuction(lot).bidData.bid;

			UserLotInfo memory user1Info = getUserLotInfo(lot, user1);
			UserLotInfo memory user2Info = getUserLotInfo(lot, user2);
			UserLotInfo memory user3Info = getUserLotInfo(lot, user3);
			UserLotInfo memory user4Info = getUserLotInfo(lot, user4);

			assertEq((expectedNonLastBidderShare * lotPrice) / 1e18, user1Info.price, "User1 price should not include bonus");
			assertEq((expectedNonLastBidderShare * lotPrice) / 1e18, user2Info.price, "User2 price should not include bonus");
			assertEq((expectedNonLastBidderShare * lotPrice) / 1e18, user3Info.price, "User3 price should not include bonus");
			assertEq((expectedLastBidderShare * lotPrice) / 1e18, user4Info.price, "User4 price should include bonus");

			assertApproxEqAbs(
				user1Info.price + user2Info.price + user3Info.price + user4Info.price,
				lotPrice,
				10,
				"Prices for all users should add up to total lot price"
			);
		}

		// CLAIMS
		{
			UserLotInfo memory user1Info = getUserLotInfo(lot, user1);
			UserLotInfo memory user2Info = getUserLotInfo(lot, user2);
			UserLotInfo memory user3Info = getUserLotInfo(lot, user3);
			UserLotInfo memory user4Info = getUserLotInfo(lot, user4);

			vm.deal(user1, user1Info.price);
			vm.prank(user1);
			auctioneer.claimLot{ value: user1Info.price }(lot, "");

			vm.deal(user2, user2Info.price);
			vm.prank(user2);
			auctioneer.claimLot{ value: user2Info.price }(lot, "");

			vm.deal(user3, user3Info.price);
			vm.prank(user3);
			auctioneer.claimLot{ value: user3Info.price }(lot, "");

			vm.deal(user4, user4Info.price);
			vm.prank(user4);
			auctioneer.claimLot{ value: user4Info.price }(lot, "");
		}
	}

	function test_runes_view_getUserLotInfo_bidCounts_AuctionWithRunes() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		uint256 user1Bids = 86;
		uint256 user2Bids = 6;
		uint256 user3Bids = 37;
		uint256 user4Bids = 123;
		uint256 rune1Bids = user1Bids + user2Bids;
		uint256 rune2Bids = user3Bids + user4Bids;
		uint256 auctionBids = rune1Bids + rune2Bids;

		_multibidWithRune(user1, lot, user1Bids, 1);
		_multibidWithRune(user2, lot, user2Bids, 1);
		_multibidWithRune(user3, lot, user3Bids, 2);
		_multibidWithRune(user4, lot, user4Bids, 2);

		assertEq(getUserLotInfo(lot, user1).bidCounts.user, user1Bids, "User1 bids should match");
		assertEq(getUserLotInfo(lot, user1).bidCounts.rune, rune1Bids, "Rune1 bids should match (user1)");
		assertEq(getUserLotInfo(lot, user1).bidCounts.auction, auctionBids, "Auction bids should match (user1)");

		assertEq(getUserLotInfo(lot, user2).bidCounts.user, user2Bids, "User2 bids should match");
		assertEq(getUserLotInfo(lot, user2).bidCounts.rune, rune1Bids, "Rune1 bids should match (user2)");
		assertEq(getUserLotInfo(lot, user2).bidCounts.auction, auctionBids, "Auction bids should match (user2)");

		assertEq(getUserLotInfo(lot, user3).bidCounts.user, user3Bids, "User3 bids should match");
		assertEq(getUserLotInfo(lot, user3).bidCounts.rune, rune2Bids, "Rune2 bids should match (user3)");
		assertEq(getUserLotInfo(lot, user3).bidCounts.auction, auctionBids, "Auction bids should match (user3)");

		assertEq(getUserLotInfo(lot, user4).bidCounts.user, user4Bids, "User4 bids should match");
		assertEq(getUserLotInfo(lot, user4).bidCounts.rune, rune2Bids, "Rune2 bids should match (user4)");
		assertEq(getUserLotInfo(lot, user4).bidCounts.auction, auctionBids, "Auction bids should match (user4)");
	}

	// RUNE SWITCH PENALTY

	function test_runeSwitchPenalty_ExpectEmit_UpdatedRuneSwitchPenalty() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedRuneSwitchPenalty(5000);

		auctioneerAuction.updateRuneSwitchPenalty(5000);
	}

	function test_runeSwitchPenalty_ValuesUpdated() public {
		assertEq(auctioneerAuction.runeSwitchPenalty(), 2000, "Initial rune switch penalty = 2000");
		auctioneerAuction.updateRuneSwitchPenalty(5000);
		assertEq(auctioneerAuction.runeSwitchPenalty(), 5000, "Updated rune switch penalty = 5000");
		auctioneerAuction.updateRuneSwitchPenalty(10000);
		assertEq(auctioneerAuction.runeSwitchPenalty(), 10000, "Updated rune switch penalty = 10000");
	}

	function test_runeSwitchPenalty_ExpectRevert_Invalid() public {
		vm.expectRevert(Invalid.selector);
		auctioneerAuction.updateRuneSwitchPenalty(10001);
	}

	// PRESELECT

	function test_runes_selectRune_ExpectEmit_SelectedRune() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		assertEq(getUserLotInfo(lot, user1).rune, 0, "User1 no rune");

		_expectEmitAuctionEvent_SwitchRune(lot, user1, "", 1);

		vm.prank(user1);
		auctioneer.selectRune(lot, 1, "");

		assertEq(getUserLotInfo(lot, user1).rune, 1, "User1 rune selected");
	}

	function test_runes_selectRune_ExpectEmit_SelectedRune_WithMessage() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		assertEq(getUserLotInfo(lot, user1).rune, 0, "User1 no rune");

		_expectEmitAuctionEvent_SwitchRune(lot, user1, "RUNE RUNE RUNE", 1);

		vm.prank(user1);
		auctioneer.selectRune(lot, 1, "RUNE RUNE RUNE");

		assertEq(getUserLotInfo(lot, user1).rune, 1, "User1 rune selected");
	}

	function test_runes_selectRune_ExpectRevert_CantCallOnRunelessAuction() public {
		uint256 lot = _createDailyAuctionWithRunes(0, true);

		vm.expectRevert(InvalidRune.selector);

		vm.prank(user1);
		auctioneer.selectRune(lot, 0, "");
	}

	function test_runes_selectRune_ExpectRevert_InvalidRune() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		vm.expectRevert(InvalidRune.selector);

		vm.prank(user1);
		auctioneer.selectRune(lot, 3, "");
	}

	// SWITCHING RUNES

	function test_selectRune_Expect_ValuesUpdatedCorrectly() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		uint256 userBids = 100;
		uint256[5] memory penalties = [uint256(0), 2000, 5000, 8000, 10000];

		uint256 snapshot = vm.snapshot();

		for (uint8 i = 0; i < penalties.length; i++) {
			vm.revertTo(snapshot);

			uint256 penalty = penalties[i];
			uint256 expectedBidsAfterPenalty = (userBids * (10000 - penalty)) / 10000;

			auctioneerAuction.updateRuneSwitchPenalty(penalty);
			assertEq(
				auctioneerAuction.runeSwitchPenalty(),
				penalty,
				string.concat("Rune switch Penalty is ", vm.toString(penalty))
			);

			// BIDS
			_multibidWithRune(user1, lot, userBids, 1);
			_multibidWithRune(user2, lot, userBids, 1);
			_multibidWithRune(user3, lot, userBids, 2);
			_multibidWithRune(user4, lot, userBids, 2);

			Auction memory auctionInit = auctioneerAuction.getAuction(lot);
			UserLotInfo memory userInfoInit = getUserLotInfo(lot, user1);

			// Auction
			assertEq(auctionInit.bidData.bids, 400, "Expect 400 Bids");
			// User
			assertEq(userInfoInit.bidCounts.user, 100, "User 1 has 100 Bids");
			assertEq(userInfoInit.rune, 1, "User 1 has selected Rune 1");
			// Runes
			assertEq(auctionInit.runes[1].bids, 200, "Rune 1 should have 200 Bids");
			assertEq(auctionInit.runes[2].bids, 200, "Rune 2 should have 200 Bids");

			// Switch Rune
			vm.prank(user1);
			auctioneer.selectRune(lot, 2, "");

			Auction memory auctionFinal = auctioneerAuction.getAuction(lot);
			UserLotInfo memory userInfoFinal = getUserLotInfo(lot, user1);
			string memory bidsAfterPenaltyStr = string.concat(" bids after ", vm.toString(penalty), "% penalty");
			uint256 auctionExpectedBids = (3 * userBids) + (1 * expectedBidsAfterPenalty);
			uint256 rune2ExpectedBids = (2 * userBids) + (1 * expectedBidsAfterPenalty);

			// Auction
			assertEq(
				auctionFinal.bidData.bids,
				auctionExpectedBids,
				string.concat("Expect ", vm.toString(auctionExpectedBids), bidsAfterPenaltyStr)
			);
			// User
			assertEq(
				userInfoFinal.bidCounts.user,
				expectedBidsAfterPenalty,
				string.concat("User 1 has ", vm.toString(expectedBidsAfterPenalty), bidsAfterPenaltyStr)
			);
			assertEq(userInfoFinal.rune, 2, "User 1 has selected Rune 2");
			// Runes
			assertEq(auctionFinal.runes[1].bids, 100, "Rune 1 should have 100 Bids");
			assertEq(
				auctionFinal.runes[2].bids,
				rune2ExpectedBids,
				string.concat("Rune 2 should have ", vm.toString(rune2ExpectedBids), bidsAfterPenaltyStr)
			);

			console.log("Penalty %s", penalty);
			console.log("  Auction bids %s -> %s", auctionInit.bidData.bids, auctionFinal.bidData.bids);
			console.log("  User bids %s -> %s", userInfoInit.bidCounts.user, userInfoFinal.bidCounts.user);
			console.log("  User rune %s -> %s", userInfoInit.rune, userInfoFinal.rune);
			console.log("  Rune 1 Bids %s -> %s", auctionInit.runes[1].bids, auctionFinal.runes[1].bids);
			console.log("  Rune 2 Bids %s -> %s", auctionInit.runes[2].bids, auctionFinal.runes[2].bids);
		}
	}

	function test_selectRune_SameRune_Expect_ValuesNotChange() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		uint256 userBids = 100;

		_multibidWithRune(user1, lot, userBids, 1);
		_multibidWithRune(user2, lot, userBids, 1);
		_multibidWithRune(user3, lot, userBids, 2);
		_multibidWithRune(user4, lot, userBids, 2);

		// Rune switch penalty
		assertEq(auctioneerAuction.runeSwitchPenalty(), 2000, "Rune switch Penalty is 20%");

		// Auction
		assertEq(auctioneerAuction.getAuction(lot).bidData.bids, 400, "Expect 400 Bids");
		// User
		assertEq(getUserLotInfo(lot, user1).bidCounts.user, 100, "User 1 has 100 Bids");
		assertEq(getUserLotInfo(lot, user1).rune, 1, "User 1 has selected Rune 1");
		// Runes
		assertEq(auctioneerAuction.getAuction(lot).runes[1].bids, 200, "Rune 1 should have 200 Bids");
		assertEq(auctioneerAuction.getAuction(lot).runes[2].bids, 200, "Rune 2 should have 200 Bids");

		// Switching to same rune doesn't incur penalty
		vm.prank(user1);
		auctioneer.selectRune(lot, 1, "");

		// Auction
		assertEq(auctioneerAuction.getAuction(lot).bidData.bids, 400, "Auction still has 400 Bids");
		// User
		assertEq(getUserLotInfo(lot, user1).bidCounts.user, 100, "User 1 still has 100 Bids");
		assertEq(getUserLotInfo(lot, user1).rune, 1, "User 1 has still selected Rune 1");
		// Runes
		assertEq(auctioneerAuction.getAuction(lot).runes[1].bids, 200, "Rune 1 should still have 200 Bids");
		assertEq(auctioneerAuction.getAuction(lot).runes[2].bids, 200, "Rune 2 should still have 200 Bids");
	}
}
