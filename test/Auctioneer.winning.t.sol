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
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: true }));
	}

	function test_winning_claimLot_ExpectEmit_ClaimedLot() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Not claimable up until end of auction
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy);

		vm.expectRevert(AuctionStillRunning.selector);
		vm.prank(user1);
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: true }));

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
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: true }));
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
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: true }));
	}

	function test_winning_claimLotWinnings_RevertWhen_UserAlreadyClaimedLot() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		// Claim once
		vm.prank(user1);
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: true }));
		assertEq(auctioneerUser.getAuctionUser(0, user1).lotClaimed, true, "AuctionUser marked as lotClaimed");

		// Revert on claim again
		vm.expectRevert(UserAlreadyClaimedLot.selector);
		vm.prank(user1);
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: true }));
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
		uint256 user1USDBalInit = USD.balanceOf(user1);

		// Claim
		vm.prank(user1);
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: true }));

		uint256 user1USDBalFinal = USD.balanceOf(user1);

		assertEq(user1USDBalInit - lotPrice, user1USDBalFinal, "Users USD balance should decrease by lot price");
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
		vm.prank(user1);
		auctioneerUser.addFunds(50e18);

		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;
		uint256 user1USDBalInit = USD.balanceOf(user1);
		uint256 user1FundsInit = auctioneerUser.userFunds(user1);

		// Claim
		vm.prank(user1);
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.FUNDS, unwrapETH: true }));

		uint256 user1USDBalFinal = USD.balanceOf(user1);
		uint256 user1FundsFinal = auctioneerUser.userFunds(user1);

		assertEq(user1USDBalInit, user1USDBalFinal, "Users USD balance should not change");
		assertEq(user1FundsInit - lotPrice, user1FundsFinal, "Users finds should decrease by lot price");
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
		auctioneerUser.addFunds(lotPrice / 2);

		vm.expectRevert(InsufficientFunds.selector);

		// Claim
		vm.prank(user1);
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.FUNDS, unwrapETH: true }));
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
		uint256 treasuryUSDInit = USD.balanceOf(treasury);
		uint256 farmUSDInit = USD.balanceOf(address(farm));

		// Claim
		vm.prank(user1);
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: true }));

		uint256 treasuryUSDFinal = USD.balanceOf(treasury);
		uint256 farmUSDFinal = USD.balanceOf(address(farm));

		assertEq(
			treasuryUSDFinal - treasuryUSDInit,
			lotPrice,
			"Treasury should receive own share + farm share (farm 0 staked fallback)"
		);
		assertEq(farmUSDFinal - farmUSDInit, 0, "Farm should receive 0 (farm 0 staked fallback)");
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
		uint256 treasuryUSDInit = USD.balanceOf(treasury);
		uint256 farmUSDInit = USD.balanceOf(address(farm));
		uint256 treasurySplit = auctioneerAuction.treasurySplit();
		uint256 treasuryCut = lotPrice.scaleByBP(treasurySplit);
		uint256 farmCut = lotPrice.scaleByBP(10000 - treasurySplit);

		uint256 usdPerShareInit = farm.getPool(goPid).accUsdPerShare;
		assertEq(usdPerShareInit, 0, "USD rew per share should start at 0");

		// Claim
		vm.prank(user1);
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: true }));

		uint256 treasuryUSDFinal = USD.balanceOf(treasury);
		uint256 farmUSDFinal = USD.balanceOf(address(farm));

		assertEq(treasuryUSDFinal - treasuryUSDInit, treasuryCut, "Treasury should receive share");
		assertEq(farmUSDFinal - farmUSDInit, farmCut, "Farm should receive share");
		assertEq(
			((treasuryUSDFinal - treasuryUSDInit) * 10000) / treasurySplit,
			((farmUSDFinal - farmUSDInit) * 10000) / (10000 - treasurySplit),
			"Farm and treasury receive correct split"
		);

		// Farm usdPerShare should increase
		uint256 expectedUsdPerShare = (farmCut * farm.REWARD_PRECISION() * farm.getPool(goPid).allocPoint) /
			(farm.totalAllocPoint() * farm.getPool(goPid).supply);
		uint256 usdPerShareFinal = farm.getPool(goPid).accUsdPerShare;
		assertEq(expectedUsdPerShare, usdPerShareFinal, "USD reward per share of farm should increase");
	}

	function test_winning_auctionIsMarkedAsClaimed() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		// Claim
		vm.prank(user1);
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: true }));
		assertEq(auctioneerUser.getAuctionUser(0, user1).lotClaimed, true, "AuctionUser marked as lotClaimed");
	}

	function test_winning_userReceivesLotTokens() public {
		vm.warp(auctioneerAuction.getAuction(1).unlockTimestamp);
		_bidOnLot(user1, 1);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(1).bidData.nextBidBy + 1);

		// Tokens init
		uint256 userETHInit = user1.balance;
		uint256 userXXInit = XXToken.balanceOf(user1);
		uint256 userYYInit = YYToken.balanceOf(user1);

		// Claim
		vm.prank(user1);
		auctioneer.claimLot(1, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: true }));

		// User received lot
		Auction memory auction = auctioneerAuction.getAuction(1);
		assertEq(user1.balance - userETHInit, auction.rewards.tokens[0].amount, "User received ETH from lot");
		assertEq(XXToken.balanceOf(user1) - userXXInit, auction.rewards.tokens[1].amount, "User received XX from lot");
		assertEq(YYToken.balanceOf(user1) - userYYInit, auction.rewards.tokens[2].amount, "User received YY from lot");
	}

	function test_winning_userCanChooseLotAsEth() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		// ETH bal
		uint256 userETHInit = user1.balance;

		// Claim
		vm.prank(user1);
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: true }));

		// ETH test
		assertEq(
			user1.balance - userETHInit,
			auctioneerAuction.getAuction(0).rewards.tokens[0].amount,
			"User received ETH from lot"
		);
	}
	function test_winning_userCanChooseLotAsWeth() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		// ETH bal
		uint256 userWETHInit = WETH.balanceOf(user1);

		// Claim
		vm.prank(user1);
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: false }));

		// ETH test
		assertEq(
			WETH.balanceOf(user1) - userWETHInit,
			auctioneerAuction.getAuction(0).rewards.tokens[0].amount,
			"User received WETH from lot"
		);
	}
}
