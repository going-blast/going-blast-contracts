// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../Auctioneer.sol";
import "../IAuctioneer.sol";
import { GOToken } from "../GOToken.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../AuctioneerFarm.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BasicERC20 } from "../BasicERC20.sol";
import { WETH9 } from "../WETH9.sol";

contract AuctioneerCreateTest is AuctioneerHelper, Test, AuctioneerEvents {
	using SafeERC20 for IERC20;

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
		auctioneer.initialize();

		// Give WETH to treasury
		vm.deal(treasury, 10e18);

		// Treasury deposit for WETH
		vm.prank(treasury);
		WETH.deposit{ value: 5e18 }();

		// Approve WETH for auctioneer
		vm.prank(treasury);
		IERC20(address(WETH)).approve(address(auctioneer), type(uint256).max);
	}

	function _getNextDay2PMTimestamp() public view returns (uint256) {
		return ((block.timestamp / 1 days) + 1) * block.timestamp + 14 hours;
	}

	function _getBaseSingleAuctionParams() public view returns (AuctionParams memory params) {
		address[] memory tokens = new address[](1);
		tokens[0] = ETH_ADDR;

		uint256[] memory amounts = new uint256[](1);
		amounts[0] = 1e18;

		BidWindowParams[] memory windows = new BidWindowParams[](3);
		windows[0] = BidWindowParams({ windowType: BidWindowType.OPEN, duration: 6 hours, timer: 0 });
		windows[1] = BidWindowParams({ windowType: BidWindowType.TIMED, duration: 2 hours, timer: 2 minutes });
		windows[2] = BidWindowParams({ windowType: BidWindowType.INFINITE, duration: 0, timer: 1 minutes });

		params = AuctionParams({
			isPrivate: true,
			emissionBP: 10000,
			tokens: tokens,
			amounts: amounts,
			name: "First Auction",
			windows: windows,
			unlockTimestamp: _getNextDay2PMTimestamp()
		});
	}

	// CREATE
	function test_createDailyAuctions_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		vm.prank(address(0));
		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_RevertWhen_NotInitialized() public {
		// SETUP
		auctioneer = new Auctioneer(USD, GO, WETH, 1e18, 1e16, 1e18, 20e18);

		// EXECUTE
		vm.expectRevert(NotInitialized.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_RevertWhen_TreasuryNotSet() public {
		// SETUP
		auctioneer = new Auctioneer(USD, GO, WETH, 1e18, 1e16, 1e18, 20e18);

		vm.prank(presale);
		GO.safeTransfer(address(auctioneer), 1e18);

		auctioneer.initialize();

		// EXECUTE
		vm.expectRevert(TreasuryNotSet.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_createSingleAuction_RevertWhen_TokenNotApproved() public {
		// SETUP
		vm.prank(treasury);
		WETH.approve(address(auctioneer), 0);

		// EXECUTE
		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(auctioneer), 0, 1e18));

		AuctionParams[] memory params = new AuctionParams[](1);

		params[0] = _getBaseSingleAuctionParams();

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_createSingleAuction_RevertWhen_BalanceInsufficient() public {
		// SETUP
		uint256 treasuryBalance = WETH.balanceOf(treasury);

		vm.prank(treasury);
		IERC20(address(WETH)).safeTransfer(deployer, treasuryBalance);

		// EXECUTE
		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, treasury, 0, 1e18));

		AuctionParams[] memory params = new AuctionParams[](1);

		params[0] = _getBaseSingleAuctionParams();

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_createSingleAuction_RevertWhen_TooManyDailyAuctions() public {
		vm.expectRevert(abi.encodeWithSelector(TooManyAuctionsPerDay.selector, 4));

		AuctionParams[] memory params = new AuctionParams[](5);

		AuctionParams memory singleAuctionParam = _getBaseSingleAuctionParams();
		singleAuctionParam.emissionBP = 1000;
		params[0] = singleAuctionParam;
		params[1] = singleAuctionParam;
		params[2] = singleAuctionParam;
		params[3] = singleAuctionParam;
		params[4] = singleAuctionParam;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_createSingleAuction_RevertWhen_InvalidDailyEmissionBP() public {
		vm.expectRevert(abi.encodeWithSelector(InvalidDailyEmissionBP.selector, 10000, 15000, 1));

		AuctionParams[] memory params = new AuctionParams[](2);

		params[0] = _getBaseSingleAuctionParams();
		params[0].emissionBP = 10000;

		params[1] = _getBaseSingleAuctionParams();
		params[1].emissionBP = 15000;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateUnlock_RevertWhen_UnlockAlreadyPassed() public {
		vm.expectRevert(UnlockAlreadyPassed.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		vm.warp(params[0].unlockTimestamp + 1);

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateTokens_RevertWhen_TooManyTokens() public {
		vm.expectRevert(TooManyTokens.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		address[] memory tokens = new address[](5);
		tokens[0] = params[0].tokens[0];
		tokens[1] = params[0].tokens[0];
		tokens[2] = params[0].tokens[0];
		tokens[3] = params[0].tokens[0];
		tokens[4] = params[0].tokens[0];

		params[0].tokens = tokens;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateTokens_RevertWhen_TokensAndAmountsLengthMismatch() public {
		vm.expectRevert(LengthMismatch.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		address[] memory tokens = new address[](2);
		tokens[0] = params[0].tokens[0];
		tokens[1] = params[0].tokens[0];

		params[0].tokens = tokens;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateTokens_RevertWhen_NoTokens() public {
		vm.expectRevert(NoTokens.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		address[] memory tokens = new address[](0);
		uint256[] memory amounts = new uint256[](0);
		params[0].tokens = tokens;
		params[0].amounts = amounts;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateBidWindows_RevertWhen_InvalidBidWindowCount_0() public {
		vm.expectRevert(InvalidBidWindowCount.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		BidWindowParams[] memory windows = new BidWindowParams[](0);
		params[0].windows = windows;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateBidWindows_RevertWhen_InvalidBidWindowCount_5() public {
		vm.expectRevert(InvalidBidWindowCount.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		BidWindowParams[] memory windows = new BidWindowParams[](5);

		windows[0] = params[0].windows[0];
		windows[1] = params[0].windows[0];
		windows[2] = params[0].windows[0];
		windows[3] = params[0].windows[1];
		windows[4] = params[0].windows[2];

		params[0].windows = windows;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateBidWindows_RevertWhen_InvalidWindowOrder() public {
		// OPEN AFTER TIMED
		vm.expectRevert(InvalidWindowOrder.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		params[0].windows[0].windowType = BidWindowType.TIMED;
		params[0].windows[1].windowType = BidWindowType.OPEN;
		params[0].windows[2].windowType = BidWindowType.TIMED;

		auctioneer.createDailyAuctions(params);

		// OPEN AFTER INFINITE
		vm.expectRevert(InvalidWindowOrder.selector);

		params[0].windows[0].windowType = BidWindowType.INFINITE;
		params[0].windows[1].windowType = BidWindowType.OPEN;
		params[0].windows[2].windowType = BidWindowType.TIMED;

		auctioneer.createDailyAuctions(params);

		// TIMED AFTER INFINITE
		vm.expectRevert(InvalidWindowOrder.selector);

		params[0].windows[0].windowType = BidWindowType.TIMED;
		params[0].windows[1].windowType = BidWindowType.INFINITE;
		params[0].windows[2].windowType = BidWindowType.OPEN;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateBidWindows_RevertWhen_LastWindowNotInfinite() public {
		vm.expectRevert(LastWindowNotInfinite.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		params[0].windows[2].windowType = BidWindowType.TIMED;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateBidWindows_RevertWhen_MultipleInfiniteWindows() public {
		vm.expectRevert(MultipleInfiniteWindows.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		params[0].windows[1].windowType = BidWindowType.INFINITE;
		params[0].windows[2].windowType = BidWindowType.INFINITE;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateBidWindows_RevertWhen_OpenWindowTooShort() public {
		vm.expectRevert(WindowTooShort.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		params[0].windows[1].duration = (1 hours - 1 seconds);

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateBidWindows_RevertWhen_InvalidBidWindowTimer() public {
		vm.expectRevert(InvalidBidWindowTimer.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		params[0].windows[2].timer = 59 seconds;

		auctioneer.createDailyAuctions(params);
	}

	// TESTS
	// [x] Validate unlock
	// [x] Validate tokens
	// [x] Validate bid windows
	// [ ] Auction created with correct data
	// [ ] Lot incremented correctly
	// [ ] Epoch emissions reduced by auction emission
}
