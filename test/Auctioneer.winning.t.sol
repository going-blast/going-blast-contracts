// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { GBMath, AuctionViewUtils } from "../src/AuctionUtils.sol";

contract AuctioneerWinningTest is AuctioneerHelper {
	using GBMath for uint256;
	using SafeERC20 for IERC20;
	using AuctionViewUtils for Auction;

	function setUp() public override {
		super.setUp();

		_distributeGO();
		_initializeAuctioneerEmissions();
		_setupAuctioneerTreasury();
		_giveUsersTokensAndApprove();
		_giveTreasuryXXandYYandApprove();

		AuctionParams[] memory params = new AuctionParams[](2);
		// Create single token auction
		params[0] = _getBaseSingleAuctionParams();
		// Create multi token auction
		params[1] = _getMultiTokenSingleAuctionParams();

		// Create single token + nfts auction
		auctioneer.createAuctions(params);
	}

	function test_winning_claimLot_RevertWhen_AuctionStillRunning() public {
		vm.expectRevert(AuctionStillRunning.selector);
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.WALLET }));
	}

	function test_winning_claimLot_ExpectEmit_ClaimedLot() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Not claimable up until end of auction
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy);

		// Price
		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;
		vm.deal(user1, lotPrice);

		vm.expectRevert(AuctionStillRunning.selector);
		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(0, ClaimLotOptions({ paymentType: PaymentType.WALLET }));

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		vm.expectEmit(true, true, true, true);
		emit ClaimedLot(
			0,
			user1,
			0,
			1e18,
			auctioneerAuction.getAuction(0).rewards.tokens,
			auctioneerAuction.getAuction(0).rewards.nfts
		);

		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(0, ClaimLotOptions({ paymentType: PaymentType.WALLET }));
	}

	function test_winning_claimLotWinnings_RevertWhen_NotWinner() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);
		assertEq(auctioneerAuction.getAuction(0).bidData.bidUser, user1, "User1 won auction");

		// User2 claim reverted
		vm.expectRevert(NotWinner.selector);
		vm.prank(user2);
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.WALLET }));
	}

	function test_winning_claimLotWinnings_RevertWhen_UserAlreadyClaimedLot() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Price
		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;
		vm.deal(user1, lotPrice);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		// Claim once
		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(0, ClaimLotOptions({ paymentType: PaymentType.WALLET }));
		assertEq(auctioneerUser.getAuctionUser(0, user1).lotClaimed, true, "AuctionUser marked as lotClaimed");

		// Revert on claim again
		vm.expectRevert(UserAlreadyClaimedLot.selector);
		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(0, ClaimLotOptions({ paymentType: PaymentType.WALLET }));
	}

	function test_winning_winnerCanPayForLotFromWallet() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_multibid(user2, 58);
		_multibid(user3, 152);
		_multibid(user4, 96);
		_multibid(user1, 110);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;
		uint256 lotPrize = 1e18;
		vm.deal(user1, lotPrice);

		_prepExpectETHBalChange(0, user1);

		// Claim
		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(0, ClaimLotOptions({ paymentType: PaymentType.WALLET }));

		_expectETHBalChange(
			0,
			user1,
			(int256(lotPrice) * -1) + int256(lotPrize),
			"User1. ETH decrease by lot price, increase by prize"
		);
	}

	function test_winning_winnerCanPayForLotFromFunds() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_multibid(user2, 58);
		_multibid(user3, 152);
		_multibid(user4, 96);
		_multibid(user1, 110);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		// Deposit into funds
		vm.deal(user1, 50e18);
		vm.prank(user1);
		auctioneerUser.addFunds{ value: 50e18 }();

		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;
		uint256 lotPrize = 1e18;
		uint256 user1FundsInit = auctioneerUser.userFunds(user1);

		_prepExpectETHBalChange(0, user1);

		// Claim
		vm.prank(user1);
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.FUNDS }));

		uint256 user1FundsFinal = auctioneerUser.userFunds(user1);

		assertEq(user1FundsInit - lotPrice, user1FundsFinal, "Users finds should decrease by lot price");
		_expectETHBalChange(0, user1, int256(lotPrize), "User1. ETH should only increase by lot prize");
	}

	function test_winning_ExpectRevert_PaymentFromFundsInsufficient() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_multibid(user2, 58);
		_multibid(user3, 152);
		_multibid(user4, 96);
		_multibid(user1, 110);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;

		// Deposit into funds
		vm.prank(user1);
		vm.deal(user1, 1e18);
		auctioneerUser.addFunds{ value: lotPrice / 2 }();

		vm.expectRevert(InsufficientFunds.selector);

		// Claim
		vm.prank(user1);
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.FUNDS }));
	}

	function test_winning_lotPriceIsDistributedCorrectly_Farm0StakedFallbackToTreasury() public {
		// Set farm
		auctioneer.updateFarm(address(farm));

		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_multibid(user2, 58);
		_multibid(user3, 152);
		_multibid(user4, 96);
		_multibid(user1, 110);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		// Finalize to distribute bidding revenue
		auctioneer.finalizeAuction(0);

		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;
		vm.deal(user1, lotPrice * 5);

		_prepExpectETHBalChange(0, treasury);
		_prepExpectETHBalChange(0, address(farm));

		// Claim
		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(0, ClaimLotOptions({ paymentType: PaymentType.WALLET }));

		_expectETHBalChange(
			0,
			treasury,
			int256(lotPrice),
			"Treasury. Should increase by full price, fallback from farm cut"
		);
		_expectETHBalChange(0, address(farm), int256(0), "Farm. Should not increase (0 staked)");
	}

	function _farmDeposit() public {
		vm.prank(treasury);
		GO.transfer(user1, 10e18);
		vm.prank(user1);
		GO.approve(address(farm), 10e18);
		vm.prank(user1);
		farm.deposit(goPid, 10e18, user1);
	}

	function test_winning_lotPriceIsDistributedCorrectly_WithoutFallback() public {
		// Set farm
		auctioneer.updateFarm(address(farm));

		// Deposit some non zero value into farm to prevent distribution fallback
		_farmDeposit();

		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_multibid(user2, 58);
		_multibid(user3, 152);
		_multibid(user4, 96);
		_multibid(user1, 110);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		// Finalize to distribute bidding revenue
		auctioneer.finalizeAuction(0);

		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;
		uint256 treasurySplit = auctioneerAuction.treasurySplit();
		uint256 treasuryCut = lotPrice.scaleByBP(treasurySplit);
		uint256 farmCut = lotPrice.scaleByBP(10000 - treasurySplit);

		_prepExpectETHBalChange(0, treasury);
		_prepExpectETHBalChange(0, address(farm));

		uint256 ethPerShareInit = farm.getPool(goPid).accEthPerShare;
		assertEq(ethPerShareInit, 0, "ETH rew per share should start at 0");

		// Claim
		vm.prank(user1);
		vm.deal(user1, lotPrice);
		auctioneer.claimLot{ value: lotPrice }(0, ClaimLotOptions({ paymentType: PaymentType.WALLET }));

		_expectETHBalChange(0, treasury, int256(treasuryCut), "Treasury. Increase by cut of lot price");
		_expectETHBalChange(0, address(farm), int256(farmCut), "Farm. Increase by cut of lot price");

		// Farm ethPerShare should increase
		uint256 expectedEthPerShare = (farmCut * farm.REWARD_PRECISION() * farm.getPool(goPid).allocPoint) /
			(farm.totalAllocPoint() * farm.getPool(goPid).supply);
		uint256 ethPerShareFinal = farm.getPool(goPid).accEthPerShare;
		assertEq(expectedEthPerShare, ethPerShareFinal, "ETH reward per share of farm should increase");
	}

	function test_winning_auctionIsMarkedAsClaimed() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		// Give ETH to pay
		vm.deal(user1, 1e18);
		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;

		// Claim
		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(0, ClaimLotOptions({ paymentType: PaymentType.WALLET }));
		assertEq(auctioneerUser.getAuctionUser(0, user1).lotClaimed, true, "AuctionUser marked as lotClaimed");
	}

	function test_winning_userReceivesLotTokens() public {
		vm.warp(auctioneerAuction.getAuction(1).unlockTimestamp);
		_bidOnLot(user1, 1);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(1).bidData.nextBidBy + 1);

		// Give ETH to pay
		vm.deal(user1, 1e18);
		uint256 lotPrice = auctioneerAuction.getAuction(1).bidData.bid;
		uint256 lotPrize = 1e18;

		// Tokens init
		_prepExpectETHBalChange(0, user1);
		uint256 userXXInit = XXToken.balanceOf(user1);
		uint256 userYYInit = YYToken.balanceOf(user1);

		// Claim
		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(1, ClaimLotOptions({ paymentType: PaymentType.WALLET }));

		// User received lot
		Auction memory auction = auctioneerAuction.getAuction(1);
		_expectETHBalChange(
			0,
			user1,
			(-1 * int256(lotPrice)) + int256(lotPrize),
			"User1. ETH decrease by price, increase by prize"
		);
		assertEq(XXToken.balanceOf(user1) - userXXInit, auction.rewards.tokens[1].amount, "User received XX from lot");
		assertEq(YYToken.balanceOf(user1) - userYYInit, auction.rewards.tokens[2].amount, "User received YY from lot");
	}

	function test_winning_userReceivesETHPrize() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);
		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;
		uint256 lotPrize = 1e18;
		vm.deal(user1, lotPrice);

		_prepExpectETHBalChange(0, user1);

		// Claim
		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(0, ClaimLotOptions({ paymentType: PaymentType.WALLET }));

		_expectETHBalChange(
			0,
			user1,
			(-1 * int256(lotPrice)) + int256(lotPrize),
			"User 1. Decrease by price increase by prize"
		);
	}
}
