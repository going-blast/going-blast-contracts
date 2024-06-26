// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { GoToken } from "../src/GoToken.sol";
import { VoucherToken } from "../src/VoucherToken.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BasicERC20, BasicERC20WithDecimals } from "../src/BasicERC20.sol";
import { BasicERC721 } from "../src/BasicERC721.sol";
import { IWETH, WETH9 } from "../src/WETH9.sol";
import { AuctioneerHarness, AuctioneerAuctionHarness } from "./AuctioneerHarness.sol";
import { Auctioneer } from "../src/Auctioneer.sol";
import { GBMath } from "../src/AuctionUtils.sol";
import { GoingBlastAirdrop } from "../src/GoingBlastAirdrop.sol";

abstract contract AuctioneerHelper is AuctioneerEvents, Test {
	using GBMath for uint256;
	using SafeERC20 for IERC20;

	// CONSTS
	uint256 public bidCost = 0.00035e18;
	uint256 public startingBid = 0.00035e18;
	uint256 public bidIncrement = 0.0000035e18;

	// DATA

	address public deployer = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
	address public sender = 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496;
	address public dead = 0x000000000000000000000000000000000000dEaD;

	address public liquidity = address(40);

	address public creator = address(45);

	address public treasury = address(50);
	address public treasury2 = address(51);

	address payable public user1;
	uint256 public user1PK;
	address payable public user2;
	uint256 public user2PK;
	address payable public user3 = payable(address(102));
	address payable public user4 = payable(address(103));
	address payable[4] public users;

	AuctioneerHarness public auctioneer;
	AuctioneerAuctionHarness public auctioneerAuction;
	GoingBlastAirdrop public airdrop;

	IWETH public WETH;
	address public ETH_ADDR = address(0);
	BasicERC20 public XXToken;
	BasicERC20 public YYToken;
	BasicERC721 public mockNFT1;
	BasicERC721 public mockNFT2;
	VoucherToken public VOUCHER;

	// SETUP

	function setLabels() public {
		vm.label(deployer, "deployer");
		vm.label(sender, "sender");
		vm.label(creator, "creator");
		vm.label(dead, "dead");
		vm.label(liquidity, "liquidity");
		vm.label(treasury, "treasury");
		vm.label(treasury2, "treasury2");
		vm.label(user1, "user1");
		vm.label(user2, "user2");
		vm.label(user3, "user3");
		vm.label(user4, "user4");
		vm.label(address(auctioneer), "auctioneer");
		vm.label(address(auctioneerAuction), "auctioneerAuction");
		vm.label(address(airdrop), "airdrop");
		vm.label(address(WETH), "WETH");
		vm.label(address(0), "ETH_0");
		vm.label(address(XXToken), "XXToken");
		vm.label(address(YYToken), "YYToken");
		vm.label(address(mockNFT1), "mockNFT1");
		vm.label(address(mockNFT2), "mockNFT2");
		vm.label(address(VOUCHER), "VOUCHER");
	}

	function setUp() public virtual {
		(address user1Temp, uint256 user1PKTemp) = makeAddrAndKey("user1");
		(address user2Temp, uint256 user2PKTemp) = makeAddrAndKey("user2");
		user1 = payable(user1Temp);
		user1PK = user1PKTemp;
		user2 = payable(user2Temp);
		user2PK = user2PKTemp;
		users = [user1, user2, user3, user4];

		WETH = IWETH(address(new WETH9()));
		VOUCHER = new VoucherToken();
		XXToken = new BasicERC20("XX", "XX");
		YYToken = new BasicERC20("YY", "YY");

		_createAndLinkAuctioneers();

		_createAndMintNFTs();

		setLabels();
	}

	// SETUP UTILS

	function _createAndLinkAuctioneers() public {
		auctioneer = new AuctioneerHarness(VOUCHER, WETH);
		auctioneerAuction = new AuctioneerAuctionHarness(address(auctioneer));

		auctioneer.link(address(auctioneerAuction));
	}

	function _setupAuctioneerTreasury() public {
		auctioneer.updateTreasury(treasury);
		_giveETH(treasury, 5e18);
		_giveWETH(treasury, 5e18);
		_approveWeth(treasury, address(auctioneer), UINT256_MAX);
	}

	function _setupAuctioneerCreator() public {
		auctioneer.grantRole(CREATOR_ROLE, creator);

		_giveETH(creator, 5e18);
		_giveWETH(creator, 5e18);
		_approveWeth(creator, address(auctioneer), UINT256_MAX);
		_creatorApproveNFTs();
	}

	function _giveUsersTokensAndApprove() public {
		for (uint8 i = 0; i < 4; i++) {
			XXToken.mint(users[i], 50e18);
			YYToken.mint(users[i], 50e18);
		}
	}

	function _createDefaultDay1Auction() public {
		_createAuction(_getBaseAuctionParams());
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

	// NFT utils

	function _createAndMintNFTs() public {
		// Create NFTs
		mockNFT1 = new BasicERC721("MOCK_NFT_1", "MOCK_NFT_1", "https://tokenBaseURI", "https://contractURI");
		mockNFT2 = new BasicERC721("MOCK_NFT_2", "MOCK_NFT_2", "https://tokenBaseURI", "https://contractURI");

		// Mint nft1
		mockNFT1.safeMint(creator);
		mockNFT1.safeMint(creator);
		mockNFT1.safeMint(creator);
		mockNFT1.safeMint(creator);

		// Mint nft2
		mockNFT2.safeMint(creator);
		mockNFT2.safeMint(creator);
		mockNFT2.safeMint(creator);
		mockNFT2.safeMint(creator);
	}

	function _creatorApproveNFTs() public {
		vm.startPrank(creator);

		// Approve nft1
		mockNFT1.approve(address(auctioneerAuction), 1);
		mockNFT1.approve(address(auctioneerAuction), 2);
		mockNFT1.approve(address(auctioneerAuction), 3);
		mockNFT1.approve(address(auctioneerAuction), 4);

		// Approve nft2
		mockNFT2.approve(address(auctioneerAuction), 1);
		mockNFT2.approve(address(auctioneerAuction), 2);
		mockNFT2.approve(address(auctioneerAuction), 3);
		mockNFT2.approve(address(auctioneerAuction), 4);

		vm.stopPrank();
	}

	// UTILS
	function e(uint256 coefficient, uint256 exponent) public pure returns (uint256) {
		return coefficient * 10 ** exponent;
	}

	function _warpToUnlockTimestamp(uint256 lot) public {
		vm.warp(auctioneerAuction.getAuction(lot).unlockTimestamp);
	}
	function _warpToAuctionEndTimestamp(uint256 lot) public {
		vm.warp(auctioneerAuction.getAuction(lot).bidData.nextBidBy + 1);
	}

	function _getNextDay2PMTimestamp() public view returns (uint256) {
		return (block.timestamp / 1 days) * 1 days + 14 hours;
	}
	function _getDayInFuture2PMTimestamp(uint256 daysInFuture) public view returns (uint256) {
		return ((block.timestamp / 1 days) + daysInFuture) * 1 days + 14 hours;
	}

	function _getBaseAuctionParams() public view returns (AuctionParams memory params) {
		TokenData[] memory tokens = new TokenData[](1);
		uint256 value = 1e18;
		tokens[0] = TokenData({ token: ETH_ADDR, amount: value });

		BidWindowParams[] memory windows = new BidWindowParams[](3);
		windows[0] = BidWindowParams({ windowType: BidWindowType.OPEN, duration: 6 hours, timer: 0 });
		windows[1] = BidWindowParams({ windowType: BidWindowType.TIMED, duration: 2 hours, timer: 2 minutes });
		windows[2] = BidWindowParams({ windowType: BidWindowType.INFINITE, duration: 0, timer: 1 minutes });

		params = AuctionParams({
			runeSymbols: new uint8[](0),
			tokens: tokens,
			nfts: new NftData[](0),
			name: "Single Token Auction",
			windows: windows,
			unlockTimestamp: _getNextDay2PMTimestamp(),
			bidCost: bidCost,
			bidIncrement: bidIncrement,
			startingBid: startingBid
		});
	}

	function _getERC20SingleAuctionParams() public view returns (AuctionParams memory params) {
		TokenData[] memory tokens = new TokenData[](1);
		tokens[0] = TokenData({ token: address(XXToken), amount: 100e18 });

		BidWindowParams[] memory windows = new BidWindowParams[](3);
		windows[0] = BidWindowParams({ windowType: BidWindowType.OPEN, duration: 6 hours, timer: 0 });
		windows[1] = BidWindowParams({ windowType: BidWindowType.TIMED, duration: 2 hours, timer: 2 minutes });
		windows[2] = BidWindowParams({ windowType: BidWindowType.INFINITE, duration: 0, timer: 1 minutes });

		params = AuctionParams({
			runeSymbols: new uint8[](0),
			tokens: tokens,
			nfts: new NftData[](0),
			name: "Single Token Auction",
			windows: windows,
			unlockTimestamp: _getNextDay2PMTimestamp(),
			bidCost: bidCost,
			bidIncrement: bidIncrement,
			startingBid: startingBid
		});
	}

	function _getNftAuctionParams() public view returns (AuctionParams memory params) {
		params = _getBaseAuctionParams();

		// Add NFTs to auction
		params.nfts = new NftData[](2);
		params.nfts[0] = NftData({ nft: address(mockNFT1), id: 3 });
		params.nfts[1] = NftData({ nft: address(mockNFT2), id: 1 });
	}

	function _getRunesAuctionParams(uint8 numberOfRunes) public view returns (AuctionParams memory params) {
		params = _getBaseAuctionParams();

		// Add RUNEs to auction
		params.runeSymbols = new uint8[](numberOfRunes);
		for (uint8 i = 0; i < numberOfRunes; i++) {
			params.runeSymbols[i] = i + 1;
		}
	}

	function _giveCreatorXXandYYandApprove() public {
		XXToken.mint(creator, 1000e18);
		YYToken.mint(creator, 1000e18);

		vm.startPrank(creator);
		XXToken.approve(address(auctioneerAuction), 1000e18);
		YYToken.approve(address(auctioneerAuction), 1000e18);
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
			tokens: tokens,
			runeSymbols: new uint8[](0),
			nfts: new NftData[](0),
			name: "Multi Token Auction",
			windows: windows,
			unlockTimestamp: _getNextDay2PMTimestamp(),
			bidCost: bidCost,
			bidIncrement: bidIncrement,
			startingBid: startingBid
		});
	}

	function _createAuction(AuctionParams memory params) public returns (uint256 lot) {
		vm.prank(creator);
		return auctioneer.createAuction(params);
	}

	function _cancelAuction(uint256 _lot) public {
		vm.prank(creator);
		auctioneer.cancelAuction(_lot);
	}

	function _createBaseAuctionOnDay(uint256 daysInFuture) internal {
		uint256 unlockTimestamp = _getDayInFuture2PMTimestamp(daysInFuture);

		AuctionParams memory params = _getBaseAuctionParams();
		params.unlockTimestamp = unlockTimestamp;

		_createAuction(params);
	}

	function _createDailyAuctionWithRunes(uint8 numRunes, bool warp) internal returns (uint256 lot) {
		AuctionParams memory params = _getRunesAuctionParams(numRunes);
		_createAuction(params);
		lot = auctioneerAuction.lotCount() - 1;

		if (warp) {
			_warpToUnlockTimestamp(lot);
		}
	}

	// EVENTS

	error OwnableUnauthorizedAccount(address account);
	error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
	error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
	event Transfer(address indexed from, address indexed to, uint256 value);

	// ACCESS CONTROL

	error AccessControlUnauthorizedAccount(address account, bytes32 role);
	bytes32 public DEFAULT_ADMIN_ROLE = 0x00;
	bytes32 public MOD_ROLE = keccak256("MOD_ROLE");
	bytes32 public CREATOR_ROLE = keccak256("CREATOR_ROLE");

	function _expectRevertNotAdmin(address account) public {
		vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, account, DEFAULT_ADMIN_ROLE));
	}
	function _expectRevertNotModerator(address account) public {
		vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, account, MOD_ROLE));
	}
	function _expectRevertNotCreator(address account) public {
		vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, account, CREATOR_ROLE));
	}

	// TOKEN / ETH MOVEMENT HELPERS

	mapping(uint256 => mapping(address => uint256)) private ethBalances;

	function _prepExpectETHBalChange(uint256 id, address add) public {
		ethBalances[id][add] = add.balance;
	}
	function _expectETHBalChange(uint256 id, address add, int256 value) public {
		_expectETHBalChange(id, add, value, "");
	}
	function _expectETHBalChange(uint256 id, address add, int256 value, string memory label) public {
		assertEq(
			add.balance,
			uint256(int256(ethBalances[id][add]) + value),
			string.concat("ETH value changed ", label)
		);
	}

	function _prepExpectETHTransfer(uint256 id, address from, address to) public {
		ethBalances[id][from] = from.balance;
		ethBalances[id][to] = to.balance;
	}
	function _expectETHTransfer(uint256 id, address from, address to, uint256 value) public {
		assertEq(from.balance, ethBalances[id][from] - value, "ETH transferred from");
		assertEq(to.balance, ethBalances[id][to] + value, "ETH transferred to");
	}

	function _expectTokenTransfer(IERC20 token, address from, address to, uint256 value) public {
		vm.expectEmit(true, true, false, true, address(token));
		emit Transfer(from, to, value);
	}

	// BIDS

	function _bidShouldRevert_AuctionEnded(address user) public {
		vm.expectRevert(AuctionEnded.selector);
		_bid(user);
	}
	function _bidShouldRevert_AuctionNotYetOpen(address user) public {
		vm.expectRevert(AuctionNotYetOpen.selector);
		_bid(user);
	}
	function _bidShouldEmit(address user) public {
		_expectEmitAuctionEvent_Bid(user, 0, 0, "", 1);
		_bid(user);
	}

	function _expectEmitAuctionEvent_Message(uint256 lot, address user, string memory message) public {
		(uint8 rune, string memory _alias) = auctioneer.getAliasAndRune(lot, user);
		vm.expectEmit(true, true, true, true);
		emit Messaged(lot, user, message, _alias, rune);
	}
	function _expectEmitAuctionEvent_Claim(uint256 lot, address user, string memory message) public {
		(uint8 rune, string memory _alias) = auctioneer.getAliasAndRune(lot, user);
		vm.expectEmit(true, true, true, true);
		emit Claimed(lot, user, message, _alias, rune);
	}
	function _expectEmitAuctionEvent_SwitchRune(
		uint256 lot,
		address user,
		string memory message,
		uint8 newRune
	) public {
		(uint8 prevRune, string memory _alias) = auctioneer.getAliasAndRune(lot, user);
		vm.expectEmit(true, true, true, true);
		emit SelectedRune(lot, user, message, _alias, newRune, prevRune);
	}
	function _expectEmitAuctionEvent_Bid(
		address user,
		uint256 lot,
		uint8 rune,
		string memory message,
		uint256 bidCount
	) public {
		(uint8 prevRune, string memory _alias) = auctioneer.getAliasAndRune(lot, user);
		uint256 expectedBid = auctioneerAuction.getAuction(lot).bidData.bid + (bidCount * bidIncrement);

		vm.expectEmit(true, true, true, true);
		emit Bid(lot, user, message, _alias, rune, prevRune, expectedBid, bidCount, block.timestamp);
	}

	function _bidWithOptions(
		address user,
		uint256 lot,
		uint8 _rune,
		string memory _message,
		uint256 _bidCount,
		PaymentType _paymentType
	) public {
		vm.prank(user);
		uint256 value = _paymentType == PaymentType.WALLET ? bidCost * _bidCount : 0;
		vm.deal(user, value);
		auctioneer.bid{ value: value }(lot, _rune, _message, _bidCount, _paymentType);
	}
	function _bidWithOptionsNoDeal(
		address user,
		uint256 lot,
		uint8 _rune,
		string memory _message,
		uint256 _bidCount,
		PaymentType _paymentType
	) public {
		vm.prank(user);
		uint256 value = _paymentType == PaymentType.WALLET ? bidCost * _bidCount : 0;
		auctioneer.bid{ value: value }(lot, _rune, _message, _bidCount, _paymentType);
	}
	function _bid(address user) public {
		_bidWithOptions(user, 0, 0, "", 1, PaymentType.WALLET);
	}
	function _bidOnLot(address user, uint256 lot) public {
		_bidWithOptions(user, lot, 0, "", 1, PaymentType.WALLET);
	}
	function _multibid(address user, uint256 bidCount) public {
		_bidWithOptions(user, 0, 0, "", bidCount, PaymentType.WALLET);
	}
	function _multibidLot(address user, uint256 bidCount, uint256 lot) public {
		_bidWithOptions(user, lot, 0, "", bidCount, PaymentType.WALLET);
	}
	function _bidUntil(address user, uint256 timer, uint256 until) public {
		while (true) {
			if (block.timestamp > until) return;
			vm.warp(block.timestamp + timer);
			_bid(user);
		}
	}
	function _bidWithRune(address user, uint256 lot, uint8 rune) internal {
		_bidWithOptions(user, lot, rune, "", 1, PaymentType.WALLET);
	}

	function _multibidWithRune(address user, uint256 lot, uint256 bidCount, uint8 rune) internal {
		_bidWithOptions(user, lot, rune, "", bidCount, PaymentType.WALLET);
	}

	// Alias helpers
	function _setUserAlias(address user, string memory userAlias) public {
		vm.prank(user);
		auctioneer.setAlias(userAlias);
	}

	// User Lot Info
	function getUserLotInfo(uint256 _lot, address _user) public view returns (UserLotInfo memory info) {
		uint256[] memory lots = new uint256[](1);
		lots[0] = _lot;
		return auctioneer.getUserLotInfos(lots, _user)[0];
	}

	// Switch Runes
	function _getBidsAfterRuneSwitchPenalty(uint256 bids) public view returns (uint256) {
		return _getBidsAfterRuneSwitchPenalty(bids, auctioneerAuction.runeSwitchPenalty());
	}
	function _getBidsAfterRuneSwitchPenalty(uint256 bids, uint256 penalty) public pure returns (uint256) {
		if (bids < 4) return bids;
		return bids.scaleByBP(10000 - penalty);
	}
}
