// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { GoToken } from "../src/GoToken.sol";
import { VoucherToken } from "../src/VoucherToken.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { BasicERC20, BasicERC20WithDecimals } from "../src/BasicERC20.sol";
import { BasicERC721 } from "../src/BasicERC721.sol";
import { IWETH, WETH9 } from "../src/WETH9.sol";
import { AuctioneerHarness } from "./AuctioneerHarness.sol";
import { Auctioneer } from "../src/Auctioneer.sol";
import { GBMath } from "../src/AuctionUtils.sol";
import { AuctioneerUser } from "../src/AuctioneerUser.sol";
import { AuctioneerEmissions } from "../src/AuctioneerEmissions.sol";

abstract contract AuctioneerHelper is AuctioneerEvents, Test {
	using GBMath for uint256;
	using SafeERC20 for IERC20;

	// DATA

	address public deployer = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
	address public sender = 0x90193C961A926261B756D1E5bb255e67ff9498A1;
	address public dead = 0x000000000000000000000000000000000000dEaD;

	address public presale = address(30);

	address public liquidity = address(40);

	address public treasury = address(50);
	address public treasury2 = address(51);

	address public user1;
	uint256 public user1PK;
	address public user2;
	uint256 public user2PK;
	address public user3 = address(102);
	address public user4 = address(103);
	address[4] public users;

	AuctioneerHarness public auctioneer;
	AuctioneerUser public auctioneerUser;
	AuctioneerEmissions public auctioneerEmissions;
	AuctioneerFarm public farm;
	uint8 usdDecimals;
	BasicERC20WithDecimals public USD;
	IWETH public WETH;
	address public ETH_ADDR = address(0);
	BasicERC20 public XXToken;
	BasicERC20 public YYToken;
	BasicERC721 public mockNFT1;
	BasicERC721 public mockNFT2;
	IERC20 public GO;
	BasicERC20 public GO_LP;
	VoucherToken public VOUCHER;

	// FARM consts
	uint256 public goPid = 0;
	uint256 public goLpPid = 1;
	uint256 public xxPid = 2;
	uint256 public yyPid = 3;

	// SETUP

	function setLabels() public {
		vm.label(deployer, "deployer");
		vm.label(sender, "sender");
		vm.label(dead, "dead");
		vm.label(presale, "presale");
		vm.label(liquidity, "liquidity");
		vm.label(treasury, "treasury");
		vm.label(treasury2, "treasury2");
		vm.label(user1, "user1");
		vm.label(user2, "user2");
		vm.label(user3, "user3");
		vm.label(user4, "user4");
		vm.label(address(auctioneer), "auctioneer");
		vm.label(address(auctioneerUser), "auctioneerUser");
		vm.label(address(auctioneerEmissions), "auctioneerEmissions");
		vm.label(address(farm), "farm");
		vm.label(address(USD), "USD");
		vm.label(address(WETH), "WETH");
		vm.label(address(0), "ETH_0");
		vm.label(address(XXToken), "XXToken");
		vm.label(address(YYToken), "YYToken");
		vm.label(address(mockNFT1), "mockNFT1");
		vm.label(address(mockNFT2), "mockNFT2");
		vm.label(address(GO), "GO");
		vm.label(address(GO_LP), "GO_LP");
		vm.label(address(VOUCHER), "VOUCHER");
	}

	function setUp() public virtual {
		(user1, user1PK) = makeAddrAndKey("user1");
		(user2, user2PK) = makeAddrAndKey("user2");
		users = [user1, user2, user3, user4];

		setLabels();

		usdDecimals = 18;
		USD = new BasicERC20WithDecimals("USD", "USD", usdDecimals);
		WETH = IWETH(address(new WETH9()));
		GO = new GoToken();
		GO_LP = new BasicERC20("UniswapV2Pair", "GO_LP");
		VOUCHER = new VoucherToken();
		XXToken = new BasicERC20("XX", "XX");
		YYToken = new BasicERC20("YY", "YY");

		_createAndLinkAuctioneers();

		_createAndMintNFTs();
	}

	// SETUP UTILS

	function _createAndLinkAuctioneers() public {
		auctioneer = new AuctioneerHarness(
			GO,
			VOUCHER,
			USD,
			WETH,
			usdDecOffset(1e18),
			usdDecOffset(0.01e18),
			usdDecOffset(1e18),
			20e18
		);
		auctioneerUser = new AuctioneerUser(USD);
		auctioneerEmissions = new AuctioneerEmissions(GO);
		farm = new AuctioneerFarm(USD, GO, VOUCHER);

		// LINK
		auctioneer.link(address(auctioneerUser), address(auctioneerEmissions));
	}

	function _setupAuctioneerTreasury() public {
		auctioneer.updateTreasury(treasury);
		_giveETH(treasury, 5e18);
		_giveWETH(treasury, 5e18);
		_approveWeth(treasury, address(auctioneer), UINT256_MAX);
		_treasuryApproveNFTs();
	}

	function _distributeGO() public {
		GO.safeTransfer(address(auctioneerEmissions), GO.totalSupply().scaleByBP(6000));
		GO.safeTransfer(presale, GO.totalSupply().scaleByBP(2000));
		GO.safeTransfer(treasury, GO.totalSupply().scaleByBP(1000));
		GO.safeTransfer(liquidity, GO.totalSupply().scaleByBP(500));
		GO.safeTransfer(address(farm), GO.totalSupply().scaleByBP(500));
	}

	function _initializeAuctioneerEmissions() public {
		auctioneerEmissions.initializeEmissions(_getNextDay2PMTimestamp());
	}

	function _auctioneerUpdateFarm() public {
		auctioneer.updateFarm(address(farm));
	}

	function _initializeFarmEmissions() public {
		uint256 farmGO = GO.balanceOf(address(farm));
		farm.initializeEmissions(farmGO, 180 days);
	}
	function _initializeFarmEmissions(uint256 farmGO) public {
		farm.initializeEmissions(farmGO, 180 days);
	}

	function _initializeFarmVoucherEmissions() public {
		VOUCHER.mint(address(farm), 100e18 * 180 days);
		farm.setVoucherEmissions(100e18 * 180 days, 180 days);
	}

	function _giveUsersTokensAndApprove() public {
		for (uint8 i = 0; i < 4; i++) {
			// Give tokens
			vm.prank(presale);
			GO.transfer(users[i], 50e18);
			USD.mint(users[i], 10000e18);
			GO_LP.mint(users[i], 50e18);
			XXToken.mint(users[i], 50e18);
			YYToken.mint(users[i], 50e18);

			// Approve
			vm.startPrank(users[i]);
			USD.approve(address(auctioneer), 10000e18);
			USD.approve(address(auctioneerUser), 10000e18);
			GO.approve(address(farm), 10000e18);
			GO_LP.approve(address(farm), 10000e18);
			XXToken.approve(address(farm), 10000e18);
			YYToken.approve(address(farm), 10000e18);
			vm.stopPrank();
		}
	}

	function _createDefaultDay1Auction() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createAuctions(params);
	}

	// TOKEN UTILS

	function _giveETH(address user, uint256 amount) public {
		vm.deal(user, amount);
	}
	function _giveWETH(address user, uint256 amount) public {
		_giveETH(user, amount);
		vm.prank(user);
		WETH.deposit{ value: amount }();
	}

	function _approveWeth(address user, address recipient, uint256 amount) public {
		vm.prank(user);
		IERC20(address(WETH)).approve(recipient, amount);
	}

	function _giveVoucher(address user, uint256 amount) public {
		VOUCHER.mint(user, amount);
	}
	function _approveVoucher(address user, address receiver, uint256 amount) public {
		vm.prank(user);
		VOUCHER.approve(receiver, amount);
	}

	function _giveGO(address user, uint256 amount) public {
		vm.prank(presale);
		GO.transfer(user, amount);
	}

	function _burnGO(address user, uint256 amount) public {
		vm.prank(user);
		GO.safeTransfer(dead, amount);
	}
	function _burnAllGO(address user) public {
		_burnGO(user, GO.balanceOf(user));
	}

	// NFT utils

	function _createAndMintNFTs() public {
		// Create NFTs
		mockNFT1 = new BasicERC721("MOCK_NFT_1", "MOCK_NFT_1", "https://tokenBaseURI", "https://contractURI");
		mockNFT2 = new BasicERC721("MOCK_NFT_2", "MOCK_NFT_2", "https://tokenBaseURI", "https://contractURI");

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
	}

	function _treasuryApproveNFTs() public {
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
	function usdDecOffset(uint256 val) public view returns (uint256) {
		return (val * 10 ** usdDecimals) / 1e18;
	}
	function e(uint256 coefficient, uint256 exponent) public pure returns (uint256) {
		return coefficient * 10 ** exponent;
	}

	function _warpToUnlockTimestamp(uint256 lot) public {
		vm.warp(auctioneer.getAuction(lot).unlockTimestamp);
	}
	function _warpToAuctionEndTimestamp(uint256 lot) public {
		vm.warp(auctioneer.getAuction(lot).bidData.nextBidBy + 1);
	}

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
			runeSymbols: new uint8[](0),
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

	function _getRunesAuctionParams(uint8 numberOfRunes) public view returns (AuctionParams memory params) {
		params = _getBaseSingleAuctionParams();

		// Add RUNEs to auction
		params.runeSymbols = new uint8[](numberOfRunes);
		for (uint8 i = 0; i < numberOfRunes; i++) {
			params.runeSymbols[i] = i + 1;
		}
	}

	function _giveTreasuryXXandYYandApprove() public {
		XXToken.mint(treasury, 1000e18);
		YYToken.mint(treasury, 1000e18);
		vm.startPrank(treasury);
		XXToken.approve(address(auctioneer), 1000e18);
		YYToken.approve(address(auctioneer), 1000e18);
		vm.stopPrank();
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
			runeSymbols: new uint8[](0),
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
		auctioneer.createAuctions(params);
	}

	function _createDailyAuctionWithRunes(uint8 numRunes, bool warp) internal returns (uint256 lot) {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getRunesAuctionParams(numRunes);
		params[0].emissionBP = 2000;
		auctioneer.createAuctions(params);
		lot = auctioneer.lotCount() - 1;

		if (warp) {
			_warpToUnlockTimestamp(lot);
		}
	}

	// EVENTS

	error OwnableUnauthorizedAccount(address account);
	error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
	error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

	event Transfer(address indexed from, address indexed to, uint256 value);

	function _expectTokenTransfer(IERC20 token, address from, address to, uint256 value) public {
		vm.expectEmit(true, true, false, true, address(token));
		emit Transfer(from, to, value);
	}

	// BIDS

	function _createDefaultBidOptions() public pure returns (BidOptions memory options) {
		options = BidOptions({ paymentType: BidPaymentType.WALLET, multibid: 1, message: "Hello World", rune: 0 });
	}

	function _createBidOptions_PaymentType(BidPaymentType paymentType) public pure returns (BidOptions memory options) {
		options = _createDefaultBidOptions();
		options.paymentType = paymentType;
	}

	function _bidShouldRevert_AuctionEnded(address user) public {
		vm.expectRevert(AuctionEnded.selector);
		_bid(user);
	}
	function _bidShouldRevert_AuctionNotYetOpen(address user) public {
		vm.expectRevert(AuctionNotYetOpen.selector);
		_bid(user);
	}
	function _bidShouldEmit(address user) public {
		uint256 expectedBid = auctioneer.getAuction(0).bidData.bid + auctioneer.bidIncrement();
		vm.expectEmit(true, true, true, true);
		BidOptions memory options = BidOptions({ paymentType: BidPaymentType.WALLET, multibid: 1, message: "", rune: 0 });
		emit Bid(0, user, expectedBid, "", options);
		_bid(user);
	}
	function _bid(address user) public {
		vm.prank(user);
		BidOptions memory options = BidOptions({ paymentType: BidPaymentType.WALLET, multibid: 1, message: "", rune: 0 });
		auctioneer.bid(0, options);
	}
	function _bidOnLot(address user, uint256 lot) public {
		vm.prank(user);
		BidOptions memory options = BidOptions({ paymentType: BidPaymentType.WALLET, multibid: 1, message: "", rune: 0 });
		auctioneer.bid(lot, options);
	}
	function _multibid(address user, uint256 bidCount) public {
		vm.prank(user);
		BidOptions memory options = BidOptions({
			paymentType: BidPaymentType.WALLET,
			multibid: bidCount,
			message: "",
			rune: 0
		});
		auctioneer.bid(0, options);
	}
	function _multibidLot(address user, uint256 bidCount, uint256 lot) public {
		vm.prank(user);
		BidOptions memory options = BidOptions({
			paymentType: BidPaymentType.WALLET,
			multibid: bidCount,
			message: "",
			rune: 0
		});
		auctioneer.bid(lot, options);
	}
	function _bidUntil(address user, uint256 timer, uint256 until) public {
		while (true) {
			if (block.timestamp > until) return;
			vm.warp(block.timestamp + timer);
			_bid(user);
		}
	}
	function _bidWithRune(address user, uint256 lot, uint8 rune) internal {
		vm.prank(user);
		auctioneer.bid(lot, BidOptions({ paymentType: BidPaymentType.WALLET, multibid: 1, message: "", rune: rune }));
	}

	function _multibidWithRune(address user, uint256 lot, uint256 multibid, uint8 rune) internal {
		vm.prank(user);
		auctioneer.bid(
			lot,
			BidOptions({ paymentType: BidPaymentType.WALLET, multibid: multibid, message: "", rune: rune })
		);
	}

	// Farm helpers
	function _farm_goPerSecond(uint256 pid) public view returns (uint256) {
		return (farm.getEmission(address(GO)).perSecond * farm.getPool(pid).allocPoint) / farm.totalAllocPoint();
	}

	// Alias helpers
	function _setUserAlias(address user, string memory userAlias) public {
		vm.prank(user);
		auctioneerUser.setAlias(userAlias);
	}
}
