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

	function _farmDeposit(address user, uint256 pid, uint256 amount) public {
		vm.prank(user);
		farm.deposit(pid, amount, user);
	}
	function _farmWithdraw(address user, uint256 pid, uint256 amount) public {
		vm.prank(user);
		farm.withdraw(pid, amount, user);
	}

	uint256 public user1Deposited = 5e18;
	uint256 public user2Deposited = 15e18;
	uint256 public user3Deposited = 0.75e18;
	uint256 public user4Deposited = 2.8e18;
	uint256 public totalDeposited = user1Deposited + user2Deposited + user3Deposited + user4Deposited;

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
			assertEq(auctionRunes[i].users, 0, "Initialized with 0 users");
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
				uint256 expectedBid = auctioneerAuction.getAuction(lot).bidData.bid + auctioneerAuction.bidIncrement();
				vm.expectEmit(true, true, true, true);
				emit Bid(
					lot,
					user1,
					expectedBid,
					"",
					BidOptions({ paymentType: PaymentType.WALLET, multibid: 1, message: "", rune: i }),
					block.timestamp
				);
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

	function test_runes_bid_Expect_UsersCountOfRuneIncremented() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		assertEq(auctioneerAuction.getAuction(lot).runes[1].users, 0, "No users have bid with rune 1 yet");
		_bidWithRune(user1, lot, 1);
		assertEq(auctioneerAuction.getAuction(lot).runes[1].users, 1, "User has bid with rune 1");
		_bidWithRune(user1, lot, 1);
		assertEq(auctioneerAuction.getAuction(lot).runes[1].users, 1, "User only added once");
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

		vm.expectRevert(NotWinner.selector);

		vm.prank(user1);
		auctioneer.claimLot(lot, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: false }));

		vm.expectEmit(true, true, true, true);
		TokenData[] memory tokens = new TokenData[](1);
		tokens[0] = TokenData({ token: ETH_ADDR, amount: 1e18 });
		NftData[] memory nfts = new NftData[](0);
		emit ClaimedLot(lot, user2, 2, 1e18, tokens, nfts);

		vm.prank(user2);
		auctioneer.claimLot(lot, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: false }));
	}

	function test_runes_win_Expect_lotClaimedSetToTrue() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		_bidWithRune(user1, lot, 1);
		_bidWithRune(user2, lot, 2);

		vm.warp(block.timestamp + 1 days);

		vm.prank(user2);
		auctioneer.claimLot(lot, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: false }));

		assertEq(auctioneerUser.getAuctionUser(lot, user2).lotClaimed, true, "User has claimed lot");
	}
	function test_runes_win_RevertWhen_AlreadyClaimed() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		_bidWithRune(user1, lot, 1);
		_bidWithRune(user2, lot, 2);

		vm.warp(block.timestamp + 1 days);

		vm.prank(user2);
		auctioneer.claimLot(lot, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: false }));

		assertEq(auctioneerUser.getAuctionUser(lot, user2).lotClaimed, true, "User has claimed lot");

		vm.expectRevert(UserAlreadyClaimedLot.selector);

		vm.prank(user2);
		auctioneer.claimLot(lot, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: false }));
	}

	function test_runes_win_Expect_0RunesUserShare100Perc() public {
		uint256 lot = _createDailyAuctionWithRunes(0, true);

		_bidWithRune(user1, lot, 0);
		_bidWithRune(user2, lot, 0);

		vm.warp(block.timestamp + 1 days);

		uint256 auctionETH = 1e18;
		uint256 lotPrice = auctioneerAuction.getAuction(lot).bidData.bid;

		_expectTokenTransfer(WETH, address(auctioneerAuction), user2, (auctionETH * 1e18) / 1e18);
		_expectTokenTransfer(USD, user2, address(auctioneer), (lotPrice * 1e18) / 1e18);

		vm.prank(user2);
		auctioneer.claimLot(lot, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: false }));
	}

	function test_runes_win_Expect_2RunesUserShareSplit() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		uint256 user1Bids = 86;
		uint256 user2Bids = 6;
		uint256 user3Bids = 37;
		uint256 user4Bids = 123;
		// uint256 rune1Bids = user1Bids + user2Bids;
		uint256 rune2Bids = user3Bids + user4Bids;

		_multibidWithRune(user1, lot, user1Bids, 1);
		_multibidWithRune(user2, lot, user2Bids, 1);
		_multibidWithRune(user3, lot, user3Bids, 2);
		_multibidWithRune(user4, lot, user4Bids, 2);

		vm.warp(block.timestamp + 1 days);

		uint256 auctionETH = 1e18;
		uint256 lotPrice = auctioneerAuction.getAuction(lot).bidData.bid;

		// Finalize auction
		auctioneer.finalizeAuction(lot);

		// USER 3
		uint256 user3Share = (user3Bids * 1e18) / rune2Bids;

		// WETH lot winnings to user3
		_expectTokenTransfer(WETH, address(auctioneerAuction), user3, (auctionETH * user3Share) / 1e18);
		// USD payment to auctioneer
		_expectTokenTransfer(USD, user3, address(auctioneer), (lotPrice * user3Share) / 1e18);
		// USD profit to treasury
		_expectTokenTransfer(USD, address(auctioneer), treasury, (lotPrice * user3Share) / 1e18);

		vm.prank(user3);
		auctioneer.claimLot(lot, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: false }));

		// USER 4
		uint256 user4Share = (user4Bids * 1e18) / rune2Bids;

		// WETH lot winnings to user4
		_expectTokenTransfer(WETH, address(auctioneerAuction), user4, (auctionETH * user4Share) / 1e18);
		// USD payment to auctioneer
		_expectTokenTransfer(USD, user4, address(auctioneer), (lotPrice * user4Share) / 1e18);
		// USD profit to treasury
		_expectTokenTransfer(USD, address(auctioneer), treasury, (lotPrice * user4Share) / 1e18);

		vm.prank(user4);
		auctioneer.claimLot(lot, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: false }));

		// Totals
		assertEq(user3Share + user4Share, 1e18, "Shares should add up to 100%");
		assertEq(
			((auctionETH * user3Share) / 1e18) + ((auctionETH * user4Share) / 1e18),
			auctionETH,
			"Lot winnings should sum to total lot winnings"
		);
		assertEq(
			((lotPrice * user3Share) / 1e18) + ((lotPrice * user4Share) / 1e18),
			lotPrice,
			"Lot winnings should sum to total lot winnings"
		);
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

		vm.expectEmit(true, true, true, true);
		emit SelectedRune(lot, user1, 1);

		vm.prank(user1);
		auctioneer.selectRune(lot, 1);

		assertEq(getUserLotInfo(lot, user1).rune, 1, "User1 rune selected");
	}

	function test_runes_selectRune_ExpectRevert_CantCallOnRunelessAuction() public {
		uint256 lot = _createDailyAuctionWithRunes(0, true);

		vm.expectRevert(InvalidRune.selector);

		vm.prank(user1);
		auctioneer.selectRune(lot, 0);
	}

	function test_runes_selectRune_ExpectRevert_InvalidRune() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		vm.expectRevert(InvalidRune.selector);

		vm.prank(user1);
		auctioneer.selectRune(lot, 3);
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
			assertEq(auctionInit.runes[1].users, 2, "Rune 1 should have 2 users");
			assertEq(auctionInit.runes[1].bids, 200, "Rune 1 should have 200 Bids");
			assertEq(auctionInit.runes[2].users, 2, "Rune 2 should have 2 users");
			assertEq(auctionInit.runes[2].bids, 200, "Rune 2 should have 200 Bids");

			// Switch Rune
			vm.prank(user1);
			auctioneer.selectRune(lot, 2);

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
			assertEq(auctionFinal.runes[1].users, 1, "Rune 1 should have 1 user (2 - 1)");
			assertEq(auctionFinal.runes[1].bids, 100, "Rune 1 should have 100 Bids");
			assertEq(auctionFinal.runes[2].users, 3, "Rune 2 should have 3 users");
			assertEq(
				auctionFinal.runes[2].bids,
				rune2ExpectedBids,
				string.concat("Rune 2 should have ", vm.toString(rune2ExpectedBids), bidsAfterPenaltyStr)
			);

			console.log("Penalty %s", penalty);
			console.log("  Auction bids %s -> %s", auctionInit.bidData.bids, auctionFinal.bidData.bids);
			console.log("  User bids %s -> %s", userInfoInit.bidCounts.user, userInfoFinal.bidCounts.user);
			console.log("  User rune %s -> %s", userInfoInit.rune, userInfoFinal.rune);
			console.log("  Rune 1 Users %s -> %s", auctionInit.runes[1].users, auctionFinal.runes[1].users);
			console.log("  Rune 1 Bids %s -> %s", auctionInit.runes[1].bids, auctionFinal.runes[1].bids);
			console.log("  Rune 2 Users %s -> %s", auctionInit.runes[2].users, auctionFinal.runes[2].users);
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
		assertEq(auctioneerAuction.getAuction(lot).runes[1].users, 2, "Rune 1 should have 2 users");
		assertEq(auctioneerAuction.getAuction(lot).runes[1].bids, 200, "Rune 1 should have 200 Bids");
		assertEq(auctioneerAuction.getAuction(lot).runes[2].users, 2, "Rune 2 should have 2 users");
		assertEq(auctioneerAuction.getAuction(lot).runes[2].bids, 200, "Rune 2 should have 200 Bids");

		// Switching to same rune doesn't incur penalty
		vm.prank(user1);
		auctioneer.selectRune(lot, 1);

		// Auction
		assertEq(auctioneerAuction.getAuction(lot).bidData.bids, 400, "Auction still has 400 Bids");
		// User
		assertEq(getUserLotInfo(lot, user1).bidCounts.user, 100, "User 1 still has 100 Bids");
		assertEq(getUserLotInfo(lot, user1).rune, 1, "User 1 has still selected Rune 1");
		// Runes
		assertEq(auctioneerAuction.getAuction(lot).runes[1].users, 2, "Rune 1 should still have 2 users");
		assertEq(auctioneerAuction.getAuction(lot).runes[1].bids, 200, "Rune 1 should still have 200 Bids");
		assertEq(auctioneerAuction.getAuction(lot).runes[2].users, 2, "Rune 2 should still have 2 users");
		assertEq(auctioneerAuction.getAuction(lot).runes[2].bids, 200, "Rune 2 should still have 200 Bids");
	}
}
