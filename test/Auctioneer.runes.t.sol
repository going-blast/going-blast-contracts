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
	function _injectFarmUSD(uint256 amount) public {
		vm.startPrank(user1);
		USD.approve(address(farm), amount);
		farm.receiveUsdDistribution(amount);
		vm.stopPrank();
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

		uint256 lot = auctioneer.lotCount() - 1;

		assertEq(auctioneer.getAuction(lot).runes.length, 0, "Auction should not have any runes");
		assertEq(auctioneer.exposed_auction_hasRunes(lot), false, "Auction should not return true from .hasRunes");
	}

	function test_runes_create_3RunesParams_4RunesInAuction() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getRunesAuctionParams(3);
		auctioneer.createAuctions(params);

		uint256 lot = auctioneer.lotCount() - 1;

		assertEq(auctioneer.getAuction(lot).runes.length, 4, "Auction should have 4 runes (1 empty + 3 real)");
		assertEq(auctioneer.exposed_auction_hasRunes(lot), true, "Auction should return true from .hasRunes");
	}

	function test_runes_create_5RunesParams_6RunesInAuction() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getRunesAuctionParams(5);
		auctioneer.createAuctions(params);

		uint256 lot = auctioneer.lotCount() - 1;

		assertEq(auctioneer.getAuction(lot).runes.length, 6, "Auction should have 6 runes (1 empty + 5 real)");
		assertEq(auctioneer.exposed_auction_hasRunes(lot), true, "Auction should return true from .hasRunes");
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

		uint256 lot = auctioneer.lotCount() - 1;

		BidRune[] memory auctionRunes = auctioneer.getAuction(lot).runes;

		for (uint8 i = 0; i <= numberOfRunes; i++) {
			assertEq(auctionRunes[i].bids, 0, "Initialized with 0 bids");
			assertEq(auctionRunes[i].users, 0, "Initialized with 0 users");
			if (i == 0) assertEq(auctionRunes[i].runeSymbol, 0, "First rune should have empty rune symbol");
			else assertEq(auctionRunes[i].runeSymbol, params[0].runeSymbols[i - 1], "Rune symbol should match");
		}
	}

	// BID

	function _innerTest_runesAgainstLot(uint8 numRunes) public {
		// console.log("Test bid rune selection, num runes: %s", numRunes);
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
				uint256 expectedBid = auctioneer.getAuction(lot).bidData.bid + auctioneer.bidIncrement();
				vm.expectEmit(true, true, true, true);
				emit Bid(
					lot,
					user1,
					expectedBid,
					"",
					BidOptions({ paymentType: BidPaymentType.WALLET, multibid: 1, message: "", rune: i })
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

	function test_runes_bid_RevertWhen_SwitchRunes() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		_bidWithRune(user1, lot, 1);
		assertEq(auctioneerUser.getAuctionUser(lot, user1).rune, 1, "Users rune should be set to 1");

		vm.expectRevert(CantSwitchRune.selector);
		_bidWithRune(user1, lot, 2);
	}

	function test_runes_bid_Expect_UsersCountOfRuneIncremented() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		assertEq(auctioneer.getAuction(lot).runes[1].users, 0, "No users have bid with rune 1 yet");
		_bidWithRune(user1, lot, 1);
		assertEq(auctioneer.getAuction(lot).runes[1].users, 1, "User has bid with rune 1");
		_bidWithRune(user1, lot, 1);
		assertEq(auctioneer.getAuction(lot).runes[1].users, 1, "User only added once");
	}

	function test_runes_bid_Expect_BidsAreAddedToRuneBids() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		assertEq(auctioneer.getAuction(lot).runes[1].bids, 0, "Rune 1 has 0 bids");
		_bidWithRune(user1, lot, 1);
		assertEq(auctioneer.getAuction(lot).runes[1].bids, 1, "Rune 1 has 1 bid");
		_bidWithRune(user1, lot, 1);
		assertEq(auctioneer.getAuction(lot).runes[1].bids, 2, "Rune 1 has 2 bids");
	}

	function test_runes_bid_Expect_AuctionBidRuneSetCorrectly() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		assertEq(auctioneer.getAuction(lot).bidData.bidRune, 0, "No rune has been bid on yet");

		_bidWithRune(user1, lot, 1);
		assertEq(auctioneer.getAuction(lot).bidData.bidRune, 1, "Rune 1 is currently winning rune");

		_bidWithRune(user2, lot, 2);
		assertEq(auctioneer.getAuction(lot).bidData.bidRune, 2, "Rune 2 is currently winning rune");
	}

	// CLAIMING

	function test_runes_win_RevertWhen_NotWinningRune() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		_bidWithRune(user1, lot, 1);
		_bidWithRune(user2, lot, 2);

		vm.warp(block.timestamp + 1 days);

		assertEq(auctioneer.exposed_auction_isEnded(lot), true, "Auction has ended");
		assertEq(auctioneer.getAuction(lot).bidData.bidRune, 2, "Rune 2 has won");

		vm.expectRevert(NotWinner.selector);

		vm.prank(user1);
		auctioneer.claimLot(lot, ClaimLotOptions({ paymentType: LotPaymentType.WALLET, unwrapETH: false }));

		vm.expectEmit(true, true, true, true);
		TokenData[] memory tokens = new TokenData[](1);
		tokens[0] = TokenData({ token: ETH_ADDR, amount: 1e18 });
		NftData[] memory nfts = new NftData[](0);
		emit UserClaimedLot(lot, user2, 2, 1e18, tokens, nfts);

		vm.prank(user2);
		auctioneer.claimLot(lot, ClaimLotOptions({ paymentType: LotPaymentType.WALLET, unwrapETH: false }));
	}

	function test_runes_win_Expect_lotClaimedSetToTrue() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		_bidWithRune(user1, lot, 1);
		_bidWithRune(user2, lot, 2);

		vm.warp(block.timestamp + 1 days);

		vm.prank(user2);
		auctioneer.claimLot(lot, ClaimLotOptions({ paymentType: LotPaymentType.WALLET, unwrapETH: false }));

		assertEq(auctioneerUser.getAuctionUser(lot, user2).lotClaimed, true, "User has claimed lot");
	}
	function test_runes_win_RevertWhen_AlreadyClaimed() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		_bidWithRune(user1, lot, 1);
		_bidWithRune(user2, lot, 2);

		vm.warp(block.timestamp + 1 days);

		vm.prank(user2);
		auctioneer.claimLot(lot, ClaimLotOptions({ paymentType: LotPaymentType.WALLET, unwrapETH: false }));

		assertEq(auctioneerUser.getAuctionUser(lot, user2).lotClaimed, true, "User has claimed lot");

		vm.expectRevert(UserAlreadyClaimedLot.selector);

		vm.prank(user2);
		auctioneer.claimLot(lot, ClaimLotOptions({ paymentType: LotPaymentType.WALLET, unwrapETH: false }));
	}

	function test_runes_win_Expect_0RunesUserShare100Perc() public {
		uint256 lot = _createDailyAuctionWithRunes(0, true);

		_bidWithRune(user1, lot, 0);
		_bidWithRune(user2, lot, 0);

		vm.warp(block.timestamp + 1 days);

		uint256 auctionETH = 1e18;
		uint256 lotPrice = auctioneer.getAuction(lot).bidData.bid;

		_expectTokenTransfer(WETH, address(auctioneer), user2, (auctionETH * 1e18) / 1e18);
		_expectTokenTransfer(USD, user2, address(auctioneer), (lotPrice * 1e18) / 1e18);

		vm.prank(user2);
		auctioneer.claimLot(lot, ClaimLotOptions({ paymentType: LotPaymentType.WALLET, unwrapETH: false }));
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
		uint256 lotPrice = auctioneer.getAuction(lot).bidData.bid;

		// Finalize auction
		auctioneer.finalizeAuction(lot);

		// USER 3
		uint256 user3Share = (user3Bids * 1e18) / rune2Bids;

		// WETH lot winnings to user3
		_expectTokenTransfer(WETH, address(auctioneer), user3, (auctionETH * user3Share) / 1e18);
		// USD payment to auctioneer
		_expectTokenTransfer(USD, user3, address(auctioneer), (lotPrice * user3Share) / 1e18);
		// USD profit to treasury
		_expectTokenTransfer(USD, address(auctioneer), treasury, (lotPrice * user3Share) / 1e18);

		vm.prank(user3);
		auctioneer.claimLot(lot, ClaimLotOptions({ paymentType: LotPaymentType.WALLET, unwrapETH: false }));

		// USER 4
		uint256 user4Share = (user4Bids * 1e18) / rune2Bids;

		// WETH lot winnings to user4
		_expectTokenTransfer(WETH, address(auctioneer), user4, (auctionETH * user4Share) / 1e18);
		// USD payment to auctioneer
		_expectTokenTransfer(USD, user4, address(auctioneer), (lotPrice * user4Share) / 1e18);
		// USD profit to treasury
		_expectTokenTransfer(USD, address(auctioneer), treasury, (lotPrice * user4Share) / 1e18);

		vm.prank(user4);
		auctioneer.claimLot(lot, ClaimLotOptions({ paymentType: LotPaymentType.WALLET, unwrapETH: false }));

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

		assertEq(auctioneerUser.getUserLotInfo(lot, user1).bidCounts.user, user1Bids, "User1 bids should match");
		assertEq(auctioneerUser.getUserLotInfo(lot, user1).bidCounts.rune, rune1Bids, "Rune1 bids should match (user1)");
		assertEq(
			auctioneerUser.getUserLotInfo(lot, user1).bidCounts.auction,
			auctionBids,
			"Auction bids should match (user1)"
		);

		assertEq(auctioneerUser.getUserLotInfo(lot, user2).bidCounts.user, user2Bids, "User2 bids should match");
		assertEq(auctioneerUser.getUserLotInfo(lot, user2).bidCounts.rune, rune1Bids, "Rune1 bids should match (user2)");
		assertEq(
			auctioneerUser.getUserLotInfo(lot, user2).bidCounts.auction,
			auctionBids,
			"Auction bids should match (user2)"
		);

		assertEq(auctioneerUser.getUserLotInfo(lot, user3).bidCounts.user, user3Bids, "User3 bids should match");
		assertEq(auctioneerUser.getUserLotInfo(lot, user3).bidCounts.rune, rune2Bids, "Rune2 bids should match (user3)");
		assertEq(
			auctioneerUser.getUserLotInfo(lot, user3).bidCounts.auction,
			auctionBids,
			"Auction bids should match (user3)"
		);

		assertEq(auctioneerUser.getUserLotInfo(lot, user4).bidCounts.user, user4Bids, "User4 bids should match");
		assertEq(auctioneerUser.getUserLotInfo(lot, user4).bidCounts.rune, rune2Bids, "Rune2 bids should match (user4)");
		assertEq(
			auctioneerUser.getUserLotInfo(lot, user4).bidCounts.auction,
			auctionBids,
			"Auction bids should match (user4)"
		);
	}
}
