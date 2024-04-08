// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IWETH } from "./WETH9.sol";
import { IAuctioneerFarm } from "./IAuctioneerFarm.sol";
import "./IAuctioneer.sol";
import { BlastYield } from "./BlastYield.sol";
import { GBMath, AuctionViewUtils, AuctionMutateUtils, AuctionParamsUtils } from "./AuctionUtils.sol";
import { IAuctioneerUser } from "./AuctioneerUser.sol";
import { IAuctioneerEmissions } from "./AuctioneerEmissions.sol";

contract Auctioneer is IAuctioneer, Ownable, ReentrancyGuard, AuctioneerEvents, IERC721Receiver, BlastYield {
	using GBMath for uint256;
	using SafeERC20 for IERC20;
	using AuctionParamsUtils for AuctionParams;
	using AuctionViewUtils for Auction;
	using AuctionMutateUtils for Auction;
	using EnumerableSet for EnumerableSet.UintSet;

	// FACETS (not really)
	IAuctioneerUser public auctioneerUser;
	IAuctioneerEmissions public auctioneerEmissions;

	// ADMIN
	address public treasury;
	address public farm;
	uint256 public treasurySplit = 2000;
	address public deadAddress = 0x000000000000000000000000000000000000dEaD;

	// CORE
	IERC20 public GO;
	IERC20 public VOUCHER;
	IWETH public WETH;
	address private ETH = address(0);

	// Auctions
	uint256 public lotCount;
	mapping(uint256 => Auction) public auctions;
	mapping(uint256 => EnumerableSet.UintSet) private auctionsOnDay;
	mapping(uint256 => uint256) public dailyCumulativeEmissionBP;

	// Bid Params
	IERC20 public USD;
	uint8 private usdDecimals;
	uint256 public bidIncrement;
	uint256 public startingBid;
	uint256 public bidCost;
	uint256 private onceTwiceBlastBonusTime = 9;
	uint256 public privateAuctionRequirement;

	// FREE BIDS using VOUCHERS

	constructor(
		IERC20 _go,
		IERC20 _voucher,
		IERC20 _usd,
		IWETH _weth,
		uint256 _bidCost,
		uint256 _bidIncrement,
		uint256 _startingBid,
		uint256 _privateRequirement
	) Ownable(msg.sender) {
		GO = _go;
		VOUCHER = _voucher;
		USD = _usd;
		usdDecimals = IERC20Metadata(address(_usd)).decimals();
		WETH = _weth;

		bidCost = _bidCost;
		bidIncrement = _bidIncrement;
		startingBid = _startingBid;
		privateAuctionRequirement = _privateRequirement;
	}

	function link(address _auctioneerUser, address _auctioneerEmissions) public onlyOwner {
		if (_auctioneerUser == address(0)) revert ZeroAddress();
		if (_auctioneerEmissions == address(0)) revert ZeroAddress();
		if (address(auctioneerUser) != address(0)) revert AlreadyLinked();
		if (address(auctioneerEmissions) != address(0)) revert AlreadyLinked();

		auctioneerEmissions = IAuctioneerEmissions(_auctioneerEmissions);
		auctioneerEmissions.link(_auctioneerUser);

		auctioneerUser = IAuctioneerUser(_auctioneerUser);
		auctioneerUser.link(_auctioneerEmissions);

		emit Linked(address(this), _auctioneerUser, _auctioneerEmissions);
	}

	// RECEIVERS

	receive() external payable {}

	function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
		return this.onERC721Received.selector;
	}

	// MODIFIERS

	modifier validAuctionLot(uint256 _lot) {
		if (_lot >= lotCount) revert InvalidAuctionLot();
		_;
	}

	modifier validRune(uint256 _lot, uint8 _rune) {
		if (auctions[_lot].runes.length > 0 && (_rune == 0 || _rune >= auctions[_lot].runes.length)) revert InvalidRune();
		if (auctions[_lot].runes.length == 0 && _rune != 0) revert InvalidRune();
		_;
	}

	// Admin

	function updateTreasury(address _treasury) public onlyOwner {
		if (_treasury == address(0)) revert ZeroAddress();
		treasury = _treasury;
		emit UpdatedTreasury(_treasury);
	}

	function updateFarm(address _farm) public onlyOwner {
		farm = _farm;
		emit UpdatedFarm(_farm);
	}

	function updateTreasurySplit(uint256 _treasurySplit) public onlyOwner {
		if (_treasurySplit > 5000) revert TooSteep();
		treasurySplit = _treasurySplit;
		emit UpdatedTreasurySplit(_treasurySplit);
	}

	function updatePrivateAuctionRequirement(uint256 _requirement) public onlyOwner {
		privateAuctionRequirement = _requirement;
		emit UpdatedPrivateAuctionRequirement(_requirement);
	}

	function updateStartingBid(uint256 _startingBid) public onlyOwner {
		// Must be between 0.5 and 2 usd
		if (_startingBid < uint256(0.5e18).transformDec(18, usdDecimals)) revert Invalid();
		if (_startingBid > uint256(2e18).transformDec(18, usdDecimals)) revert Invalid();

		startingBid = _startingBid;
		emit UpdatedStartingBid(_startingBid);
	}

	// Will not update the bid cost of any already created auctions
	function updateBidCost(uint256 _bidCost) public onlyOwner {
		// Must be between 0.5 and 2 usd
		if (_bidCost < uint256(0.5e18).transformDec(18, usdDecimals)) revert Invalid();
		if (_bidCost > uint256(2e18).transformDec(18, usdDecimals)) revert Invalid();

		bidCost = _bidCost;
		emit UpdatedBidCost(_bidCost);
	}

	// BLAST

	function initializeBlast() public onlyOwner {
		_initializeBlast(address(USD), address(WETH));
	}
	function claimYieldAll(
		address _recipient,
		uint256 _amountWETH,
		uint256 _amountUSDB,
		uint256 _minClaimRateBips
	) public onlyOwner {
		_claimYieldAll(_recipient, _amountWETH, _amountUSDB, _minClaimRateBips);
	}

	// PRIVATE AUCTION

	function _userGOBalance(address _user) internal view returns (uint256 bal) {
		bal = GO.balanceOf(_user);
		if (farm != address(0)) {
			bal += IAuctioneerFarm(farm).getEqualizedUserStaked(_user);
		}
	}

	///////////////////
	// CORE
	///////////////////
	function createAuctions(AuctionParams[] memory _params) public onlyOwner nonReentrant {
		if (!auctioneerEmissions.emissionsInitialized()) revert EmissionsNotInitialized();
		if (treasury == address(0)) revert TreasuryNotSet();

		for (uint8 i = 0; i < _params.length; i++) {
			createAuction(_params[i]);
		}
	}

	function createAuction(AuctionParams memory _params) internal {
		// Validate params
		_params.validate();

		uint256 lot = lotCount;
		uint256 day = _params.unlockTimestamp / 1 days;

		Auction storage auction = auctions[lot];

		// Validate that day has room for auction
		auctionsOnDay[day].add(lot);
		if ((auctionsOnDay[day].values().length) > 4) revert TooManyAuctionsPerDay();

		// Check that days emission doesn't exceed allowable bonus (30000)
		// Most days, the emission will be 10000
		// An emission BP over 10000 means it is using emissions scheduled for other days
		// Auction emissions for the remainder of the epoch will be reduced
		// This will never overflow the emissions though, because the emission amount is calculated from remaining emissions
		dailyCumulativeEmissionBP[day] += _params.emissionBP;
		if (dailyCumulativeEmissionBP[day] > 30000) revert InvalidDailyEmissionBP();

		// Base data
		auction.lot = lot;
		auction.day = day;
		auction.name = _params.name;
		auction.isPrivate = _params.isPrivate;
		auction.unlockTimestamp = _params.unlockTimestamp;
		auction.addBidWindows(_params, onceTwiceBlastBonusTime);
		auction.finalized = false;

		// Rewards
		auction.addRewards(_params);
		auction.transferLotFrom(treasury, ETH, address(WETH));

		// Emissions
		uint256 auctionEmissions = auctioneerEmissions.allocateAuctionEmissions(
			_params.unlockTimestamp,
			_params.emissionBP
		);
		auction.emissions.bp = _params.emissionBP;
		auction.emissions.biddersEmission = auctionEmissions.scaleByBP(9000);
		auction.emissions.treasuryEmission = auctionEmissions.scaleByBP(1000);

		// Initial bidding data
		auction.bidData.revenue = 0;
		auction.bidData.bids = 0;
		auction.bidData.bid = startingBid;
		auction.bidData.bidTimestamp = _params.unlockTimestamp;
		auction.bidData.nextBidBy = auction.getNextBidBy();
		auction.bidData.usdDecimals = usdDecimals;

		// Runes
		auction.addRunes(_params);

		// Frozen bidCost to prevent a change from messing up revenue calculations
		auction.bidData.bidCost = bidCost;

		lotCount++;
		emit AuctionCreated(lot);
	}

	// CANCEL

	function cancelAuction(uint256 _lot, bool _unwrapETH) public validAuctionLot(_lot) onlyOwner {
		Auction storage auction = auctions[_lot];

		// Auction only cancellable if it doesn't have any bids, or if its already been finalized
		if (auction.bidData.bids > 0 || auction.finalized) revert NotCancellable();

		// Transfer lot tokens and nfts back to treasury
		auction.transferLotTo(treasury, 1e18, _unwrapETH, ETH, address(WETH));

		// Revert day's accumulators
		auctionsOnDay[auction.day].remove(_lot);
		dailyCumulativeEmissionBP[auction.day] -= auction.emissions.bp;

		// Cancel emissions
		auctioneerEmissions.deAllocateEmissions(
			auction.unlockTimestamp,
			auction.emissions.biddersEmission + auction.emissions.treasuryEmission
		);
		auction.emissions.bp = 0;
		auction.emissions.biddersEmission = 0;
		auction.emissions.treasuryEmission = 0;

		// Finalize to prevent bidding and claiming lot
		auction.finalized = true;

		emit AuctionCancelled(_lot);
	}

	function _selfPermit(PermitData memory _permitData) internal {
		IERC20Permit(_permitData.token).permit(
			msg.sender,
			address(this),
			_permitData.value,
			_permitData.deadline,
			_permitData.v,
			_permitData.r,
			_permitData.s
		);
	}

	function bidWithPermit(uint256 _lot, BidOptions memory _options, PermitData memory _permitData) public nonReentrant {
		_selfPermit(_permitData);
		_bid(_lot, _options);
	}

	function bid(uint256 _lot, BidOptions memory _options) public nonReentrant {
		_bid(_lot, _options);
	}

	function _bid(
		uint256 _lot,
		BidOptions memory _options
	) internal validAuctionLot(_lot) validRune(_lot, _options.rune) {
		Auction storage auction = auctions[_lot];
		auction.validateBiddingOpen();

		// VALIDATE: User can participate in auction
		if (auction.isPrivate && _userGOBalance(msg.sender) < privateAuctionRequirement) revert PrivateAuction();

		// Force bid count to be at least one
		if (_options.multibid == 0) _options.multibid = 1;

		// Update auction with new bid
		auction.bidData.bid += bidIncrement * _options.multibid;
		auction.bidData.bidUser = msg.sender;
		auction.bidData.bidTimestamp = block.timestamp;
		if (_options.paymentType != BidPaymentType.VOUCHER) {
			auction.bidData.revenue += auction.bidData.bidCost * _options.multibid;
		}
		auction.bidData.bids += _options.multibid;
		auction.bidData.nextBidBy = auction.getNextBidBy();

		// User bid
		bool isUsersFirstBid = auctioneerUser.bid(
			_lot,
			msg.sender,
			auction.bidData.bid,
			auction.emissions.biddersEmission,
			_options
		);

		// Runes
		if (auction.runes.length > 0) {
			// Add user to rune if first bid in this auction
			if (isUsersFirstBid) {
				auction.runes[_options.rune].users += 1;
			}

			// Add bids to rune, used for calculating emissions
			auction.runes[_options.rune].bids += _options.multibid;

			// Mark bidRune
			auction.bidData.bidRune = _options.rune;
		}

		// Pay for bid
		if (_options.paymentType == BidPaymentType.WALLET) {
			USD.safeTransferFrom(msg.sender, address(this), (auction.bidData.bidCost * _options.multibid));
		}
		if (_options.paymentType == BidPaymentType.FUNDS) {
			auctioneerUser.payFromFunds(msg.sender, auction.bidData.bidCost * _options.multibid);
		}
		if (_options.paymentType == BidPaymentType.VOUCHER) {
			VOUCHER.safeTransferFrom(msg.sender, deadAddress, _options.multibid * 1e18);
		}
	}

	function claimLotWithPermit(
		uint256 _lot,
		ClaimLotOptions memory _options,
		PermitData memory _permitData
	) public nonReentrant {
		_selfPermit(_permitData);
		_claimLot(_lot, _options);
	}

	function claimLot(uint256 _lot, ClaimLotOptions memory _options) public nonReentrant {
		_claimLot(_lot, _options);
	}

	function _claimLot(uint256 _lot, ClaimLotOptions memory _options) internal validAuctionLot(_lot) {
		Auction storage auction = auctions[_lot];
		auction.validateEnded();

		// Mark user claimed
		(uint8 rune, uint256 userBids) = auctioneerUser.claimLot(_lot, msg.sender);

		auction.validateWinner(msg.sender, rune);

		uint256 userShareOfLot = auction.runes.length > 0 ? (userBids * 1e18) / auction.runes[rune].bids : 1e18;
		uint256 userShareOfPayment = (auction.bidData.bid * userShareOfLot) / 1e18;

		// Transfer lot to user
		auction.transferLotTo(msg.sender, userShareOfLot, _options.unwrapETH, ETH, address(WETH));

		// Pay for lot
		if (_options.paymentType == LotPaymentType.FUNDS) {
			auctioneerUser.payFromFunds(msg.sender, userShareOfPayment);
		}
		if (_options.paymentType == LotPaymentType.WALLET) {
			USD.safeTransferFrom(msg.sender, address(this), userShareOfPayment);
		}

		// Distribute payment
		auction.distributeLotProfit(USD, userShareOfPayment, treasury, farm, treasurySplit);

		emit UserClaimedLot(auction.lot, msg.sender, rune, userShareOfLot, auction.rewards.tokens, auction.rewards.nfts);

		// Finalize
		if (!auction.finalized) {
			finalize(auction);
		}
	}

	// FINALIZE

	function finalizeAuction(uint256 _lot) public validAuctionLot(_lot) nonReentrant {
		Auction storage auction = auctions[_lot];

		// Exit if already finalized
		if (auction.finalized) return;

		auction.validateEnded();

		// FALLBACK: cancel auction instead of finalizing if auction has 0 bids
		if (auction.bidData.bids == 0) {
			cancelAuction(_lot, true);
			return;
		}

		// Finalize
		finalize(auction);
	}

	function finalize(Auction storage auction) internal {
		// Distribute lot revenue to treasury and farm
		auction.distributeLotRevenue(USD, treasury, farm, treasurySplit);

		// Send marked emissions to treasury
		auctioneerEmissions.transferEmissions(treasury, auction.emissions.treasuryEmission);

		// Mark Finalized
		auction.finalized = true;

		emit AuctionFinalized(auction.lot);
	}

	// HARVEST

	function harvestAuctionsEmissions(uint256[] memory _lots) public nonReentrant {
		for (uint256 i = 0; i < _lots.length; i++) {
			harvestAuctionEmissions(_lots[i]);
		}
	}

	function harvestAuctionEmissions(uint256 _lot) internal validAuctionLot(_lot) {
		auctions[_lot].validateEnded();

		auctioneerUser.harvestAuctionEmissions(
			_lot,
			msg.sender,
			auctions[_lot].day * 1 days,
			auctions[_lot].bidData.bids,
			auctions[_lot].emissions.biddersEmission
		);
	}

	// FUNDS
	function approveWithdrawUserFunds(uint256 _amount) public {
		if (msg.sender != address(auctioneerUser)) revert NotAuctioneerUser();
		USD.approve(address(auctioneerUser), _amount);
	}

	// VIEW

	function getAuction(uint256 _lot) public view validAuctionLot(_lot) returns (Auction memory) {
		return auctions[_lot];
	}

	function getAuctionsPerDay(uint256 _day) public view returns (uint256) {
		return auctionsOnDay[_day].values().length;
	}

	function getAuctionsOnDay(uint256 _day) public view returns (uint256[] memory) {
		return auctionsOnDay[_day].values();
	}

	function getDailyAuctionsMinimalData(
		uint256 lookBackDays,
		uint256 lookForwardDays
	) public view returns (DailyAuctionsMinimalData[] memory data) {
		uint256 currentDay = block.timestamp / 1 days;
		uint256[] memory dayLots;
		uint256 day = currentDay - lookBackDays;
		data = new DailyAuctionsMinimalData[](lookBackDays + 1 + lookForwardDays);
		for (uint256 dayIndex = 0; dayIndex < (lookBackDays + 1 + lookForwardDays); dayIndex++) {
			dayLots = auctionsOnDay[day].values();
			data[dayIndex].day = day;
			data[dayIndex].auctions = new AuctionMinimalData[](dayLots.length);

			for (uint256 dayLotIndex = 0; dayLotIndex < dayLots.length; dayLotIndex++) {
				data[dayIndex].auctions[dayLotIndex] = AuctionMinimalData({
					lot: dayLots[dayLotIndex],
					fastPolling: day == currentDay || !auctions[dayLots[dayLotIndex]].isEnded()
				});
			}

			day++;
		}
	}

	function getAuctionExt(
		uint256 _lot
	) public view validAuctionLot(_lot) returns (Auction memory auction, AuctionExt memory ext) {
		auction = auctions[_lot];
		ext = AuctionExt({
			lot: auction.lot,
			blockTimestamp: block.timestamp,
			activeWindow: auctions[_lot].activeWindow(),
			isBiddingOpen: auctions[_lot].isBiddingOpen(),
			isEnded: auctions[_lot].isEnded()
		});
	}

	function getUserPrivateAuctionsPermitted(address _user) public view returns (bool) {
		return _userGOBalance(_user) >= privateAuctionRequirement;
	}
}
