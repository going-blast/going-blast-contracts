// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IAuctioneerFarm } from "./IAuctioneerFarm.sol";
import "./IAuctioneer.sol";
import { BlastYield } from "./BlastYield.sol";
import { GBMath, AuctionViewUtils, AuctionMutateUtils, AuctionParamsUtils } from "./AuctionUtils.sol";

//         ,                ,              ,   *,    ,  , ,   *,     ,
//                               , , , ,   * * ,*     , *,,       ,      ,    .
//   .    .              .*   ,    ,,, *      , *  ,,  ,,      *
//               ,      ,   , ,  , ,       ,,** *   ,     *     ,,  ,  ,
// *           *      ,            ,,,*, * @ ,  ,,   ,     ,,
//           ,  ,       *      *  , ,,    ,@,,,,   ,, ,    , *  ,
//      , *   *   , ,           ,     **,,,@*,*,   * *,,  *       ,             ,
//       ,   ,  * ,   ,*,*  ,*  ,,  , , *  @/*/* ,, , ,   , ,     ,         ,
//       ,     *  *    *    *  , ,,,, , */*@// * ,,, , ,  ,, ,
//      *      ,,    ,, , ,  ,,    ** ,/ (*@/(*,,   ,    ,  ,   ,
//       *  *,    * , , ,, ,  , *,,..  ./*/@///,*,,* *,,      ,
//            , ,*,,* , ,  ** , ,,,,,*,//(%@&((/,/,.*.*.*  ., ., .     .
// *,    ., .,    *,,   ., ,*    .***/(%@@/@(@@/(/**.*,*,,,   .     .. ..... . .
// ,,,...    ,,   *  **  , *,,*,,**//@@*(/*@/  /@@//,,*,*,    ,,
//    *,*  *,   , ,  ,,  *  *,*,*((@@//,//*@/    (@@/*,,   ,        ,
//    , * ,* ,  ,,   ,  *, ***/*@@*/* ***/,@//* *//(*@@** ,  ,
//   ,    *   * , ,,*  *, * ,,@@*,*,,*,**,*@*/,* ,,,*//@@  ,,
//  ,,  ,,,,  , ,    *, ,,,*,,,,@@,,***,,*,@**,*,**,/@@,*, ,    ,,
// ,*    ,,, ,   ,  ,,  , , , ,,,/*@@***,, @*,,,,*@@,/,*,,,,
//    , *,,  , , **   , , ,, ,,  **,*@@,*/,@,, /@@*/** ,     ,
//   *      * *, ,,      ,,  **  * *,***@@ @*@@*/*,* ,  , ,
//         , *    ,, ,  ,    , , *,  **,**%@&,,,*, ,      ,
//          ,    *, ,,  *    , , *,,**   ,,@,,,  ,,       ,
//     *,   ,*  ,* *,  ,* , , ,, ,,*,,*,,* @,**   ,,
//    *   **     *    *   /  ,    ,, , *  ,@*, ,*, ,,     ,    ,
// *   ,, * ,,             ,  , ** ,**,, , @ *    ,
//        ,*, * ** ,*     ,,  *  ,,  *,  ,,@, ,,,*   ,
//               ,     /**,  ,   *  ,,  ,  @  ,       , ,
//        ,  /* * /     * *   *  ,*,,,  ,* @,, ,  ,        ,      ,
//   ,         ,*            ,,* *,   ,   **                        ,
//      * ,            *,  ,      ,,    ,   , ,,    ,     ,
// ,,         ,    ,      ,           ,    *

interface IAuctioneerAuction {
	function link() external;
	function runeSwitchPenalty() external view returns (uint256);
	function runicLastBidderBonus() external view returns (uint256);
	function updateTreasury(address _treasury) external;
	function privateAuctionRequirement() external view returns (uint256);
	function createAuction(AuctionParams memory _params, uint256 _emissions) external payable returns (uint256 lot);
	function cancelAuction(uint256 _lot) external returns (uint256 unlockTimestamp, uint256 cancelledEmissions);
	function markBid(
		uint256 _lot,
		address _user,
		uint256 _prevUserBids,
		uint8 _prevRune,
		uint256 _userGoBalance,
		BidOptions memory _options
	) external returns (uint256 userBid, uint256 bidCost, bool actionHasEmissions);
	function selectRune(uint256 _lot, uint256 _userBids, uint8 _prevRune, uint8 _rune) external;
	function claimLot(
		uint256 _lot,
		address _user,
		uint256 _userBids,
		uint8 _userRune
	) external returns (uint256 userShareOfLot, uint256 userShareOfPayment, bool triggerFinalization);
	function finalizeAuction(
		uint256 _lot
	)
		external
		returns (
			bool triggerCancellation,
			uint256 treasuryEmissions,
			uint256 treasuryETHDistribution,
			uint256 farmETHDistribution
		);
	function getProfitDistributions(
		uint256 _lot,
		uint256 _amount
	) external view returns (uint256 treasuryDistribution, uint256 farmDistribution);
	function validateAndGetHarvestData(
		uint256 _lot
	) external view returns (uint256 unlockTimestamp, uint256 bids, uint256 biddersEmissions);

	function getAuction(uint256 _lot) external view returns (Auction memory auction);
}

contract AuctioneerAuction is
	IAuctioneerAuction,
	Ownable,
	ReentrancyGuard,
	AuctioneerEvents,
	IERC721Receiver,
	BlastYield
{
	using GBMath for uint256;
	using SafeERC20 for IERC20;
	using AuctionParamsUtils for AuctionParams;
	using AuctionViewUtils for Auction;
	using AuctionMutateUtils for Auction;
	using EnumerableSet for EnumerableSet.UintSet;

	// ADMIN
	bool public linked;
	address public auctioneer;
	address public treasury;
	uint256 public treasurySplit = 2000;
	address public deadAddress = 0x000000000000000000000000000000000000dEaD;

	// Auctions
	uint256 public lotCount;
	mapping(uint256 => Auction) public auctions;
	mapping(uint256 => EnumerableSet.UintSet) private auctionsOnDay;
	mapping(uint256 => uint256) public dailyCumulativeEmissionBP;

	// Bid Params
	uint256 public bidIncrement;
	uint256 public startingBid;
	uint256 public bidCost;
	uint256 public runeSwitchPenalty = 2000;
	uint256 public onceTwiceBlastBonusTime = 9;
	uint256 public privateAuctionRequirement;
	uint256 public runicLastBidderBonus = 2000;

	constructor(
		uint256 _bidCost,
		uint256 _bidIncrement,
		uint256 _startingBid,
		uint256 _privateAuctionRequirement
	) Ownable(msg.sender) {
		bidCost = _bidCost;
		bidIncrement = _bidIncrement;
		startingBid = _startingBid;
		privateAuctionRequirement = _privateAuctionRequirement;
	}

	function link() public {
		if (linked) revert AlreadyLinked();
		linked = true;
		auctioneer = msg.sender;
	}

	// RECEIVERS

	receive() external payable {}

	function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
		return this.onERC721Received.selector;
	}

	// MODIFIERS

	modifier onlyAuctioneer() {
		if (msg.sender != auctioneer) revert NotAuctioneer();
		_;
	}

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

	function updateTreasury(address _treasury) public onlyAuctioneer {
		treasury = _treasury;
	}

	function updateTreasurySplit(uint256 _treasurySplit) public onlyOwner {
		if (_treasurySplit > 5000) revert TooSteep();
		treasurySplit = _treasurySplit;
		emit UpdatedTreasurySplit(_treasurySplit);
	}

	function updateStartingBid(uint256 _startingBid) public onlyOwner {
		// Difficult to set realistic limits to the starting bid
		if (_startingBid == 0) revert Invalid();
		if (_startingBid > 0.1e18) revert Invalid();

		startingBid = _startingBid;
		emit UpdatedStartingBid(_startingBid);
	}

	// Will not update the bid cost of any already created auctions
	function updateBidCost(uint256 _bidCost) public onlyOwner {
		// Difficult to set realistic limits to the bid cost
		if (_bidCost == 0) revert Invalid();
		if (_bidCost > 0.1e18) revert Invalid();

		bidCost = _bidCost;
		emit UpdatedBidCost(_bidCost);
	}

	function updatePrivateAuctionRequirement(uint256 _requirement) public onlyOwner {
		privateAuctionRequirement = _requirement;
		emit UpdatedPrivateAuctionRequirement(_requirement);
	}

	function updateRuneSwitchPenalty(uint256 _penalty) public onlyOwner {
		if (_penalty > 10000) revert Invalid();
		runeSwitchPenalty = _penalty;
		emit UpdatedRuneSwitchPenalty(_penalty);
	}

	function updateRunicLastBidderBonus(uint256 _bonus) public onlyOwner {
		if (_bonus > 5000) revert Invalid();
		runicLastBidderBonus = _bonus;
		emit UpdatedRunicLastBidderBonus(_bonus);
	}

	// BLAST

	function initializeBlast() public onlyOwner {
		_initializeBlast();
	}
	function claimYieldAll(address _recipient, uint256 _minClaimRateBips) public onlyOwner {
		_claimYieldAll(_recipient, _minClaimRateBips);
	}

	// CREATE

	function createAuction(
		AuctionParams memory _params,
		uint256 _emissions
	) external payable onlyAuctioneer returns (uint256 lot) {
		// Validate params
		_params.validate();

		lot = lotCount;
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
		auction.transferLotFrom(treasury);

		auction.emissions.bp = _params.emissionBP;
		auction.emissions.biddersEmission = _emissions.scaleByBP(9000);
		auction.emissions.treasuryEmission = _emissions.scaleByBP(1000);

		// Initial bidding data
		auction.bidData.revenue = 0;
		auction.bidData.bids = 0;
		auction.bidData.bid = startingBid;
		auction.bidData.bidTimestamp = _params.unlockTimestamp;
		auction.bidData.nextBidBy = auction.getNextBidBy();

		// Runes
		auction.addRunes(_params);

		// Frozen bidCost to prevent a change from messing up revenue calculations
		auction.bidData.bidCost = bidCost;

		lotCount++;
	}

	// CANCEL

	function cancelAuction(
		uint256 _lot
	) external onlyAuctioneer validAuctionLot(_lot) returns (uint256 unlockTimestamp, uint256 cancelledEmissions) {
		Auction storage auction = auctions[_lot];

		// Auction only cancellable if it doesn't have any bids, or if its already been finalized
		if (auction.bidData.bids > 0 || auction.finalized) revert NotCancellable();

		// Transfer lot tokens and nfts back to treasury
		auction.transferLotTo(treasury, 1e18);

		// Revert day's accumulators
		auctionsOnDay[auction.day].remove(_lot);
		dailyCumulativeEmissionBP[auction.day] -= auction.emissions.bp;

		// Cancel emissions data
		unlockTimestamp = auction.unlockTimestamp;
		cancelledEmissions = auction.emissions.biddersEmission + auction.emissions.treasuryEmission;

		// Clear auctions emissions
		auction.emissions.bp = 0;
		auction.emissions.biddersEmission = 0;
		auction.emissions.treasuryEmission = 0;

		// Finalize to prevent bidding and claiming lot
		auction.finalized = true;
	}

	// BID

	function _switchRuneUpdateData(uint256 _lot, uint256 _userBids, uint8 _prevRune, uint8 _newRune) internal {
		if (_prevRune == _newRune) return;

		// Remove data from prevRune
		if (_prevRune != 0) {
			auctions[_lot].runes[_prevRune].users -= 1;
			if (_userBids > 0) {
				auctions[_lot].runes[_prevRune].bids -= _userBids;
			}
		}

		auctions[_lot].runes[_newRune].users += 1;

		if (_userBids > 0) {
			auctions[_lot].runes[_newRune].bids += _userBids.scaleByBP(10000 - runeSwitchPenalty);
			auctions[_lot].bidData.bids =
				auctions[_lot].bidData.bids +
				_userBids.scaleByBP(10000 - runeSwitchPenalty) -
				_userBids;
		}
	}

	function markBid(
		uint256 _lot,
		address _user,
		uint256 _prevUserBids,
		uint8 _prevRune,
		uint256 _userGoBalance,
		BidOptions memory _options
	)
		external
		onlyAuctioneer
		validAuctionLot(_lot)
		validRune(_lot, _options.rune)
		returns (uint256 userBid, uint256 auctionBidCost, bool auctionHasEmissions)
	{
		Auction storage auction = auctions[_lot];
		auction.validateBiddingOpen();

		// VALIDATE: User can participate in auction
		if (auction.isPrivate && _userGoBalance < privateAuctionRequirement) revert PrivateAuction();

		// Update auction with new bid
		auction.bidData.bid += bidIncrement * _options.multibid;
		auction.bidData.bidUser = _user;
		auction.bidData.bidTimestamp = block.timestamp;
		if (_options.paymentType != PaymentType.VOUCHER) {
			auction.bidData.revenue += auction.bidData.bidCost * _options.multibid;
		}
		auction.bidData.bids += _options.multibid;
		auction.bidData.nextBidBy = auction.getNextBidBy();

		if (_prevUserBids == 0) {
			auction.users += 1;
		}

		// Runes
		if (auction.runes.length > 0) {
			_switchRuneUpdateData(_lot, _prevUserBids, _prevRune, _options.rune);
			auction.runes[_options.rune].bids += _options.multibid;
			auction.bidData.bidRune = _options.rune;
		}

		userBid = auction.bidData.bid;
		auctionBidCost = auction.bidData.bidCost;
		auctionHasEmissions = auction.emissions.biddersEmission > 0;
	}

	function selectRune(
		uint256 _lot,
		uint256 _userBids,
		uint8 _prevRune,
		uint8 _rune
	) external onlyAuctioneer validAuctionLot(_lot) validRune(_lot, _rune) {
		if (auctions[_lot].runes.length == 0) revert InvalidRune();
		_switchRuneUpdateData(_lot, _userBids, _prevRune, _rune);
	}

	// CLAIM

	function claimLot(
		uint256 _lot,
		address _user,
		uint256 _userBids,
		uint8 _userRune
	)
		public
		onlyAuctioneer
		validAuctionLot(_lot)
		returns (uint256 userShareOfLot, uint256 userShareOfPayment, bool triggerFinalization)
	{
		Auction storage auction = auctions[_lot];

		auction.validateEnded();
		auction.validateWinner(_user, _userRune);

		// Calculate the user's share, dependent on rune / no rune
		bool auctionHasRunes = auction.runes.length > 0;
		bool isLastBidder = auction.bidData.bidUser == _user;
		uint256 runicLastBidderBonusBids = isLastBidder && auctionHasRunes
			? auction.runes[_userRune].bids.scaleByBP(runicLastBidderBonus)
			: 0;
		userShareOfLot = auctionHasRunes
			? ((_userBids + runicLastBidderBonusBids) * 1e18) /
				auction.runes[_userRune].bids.scaleByBP(10000 + runicLastBidderBonus)
			: 1e18;
		userShareOfPayment = (auction.bidData.bid * userShareOfLot) / 1e18;

		// Transfer lot to user
		auction.transferLotTo(_user, userShareOfLot);

		// Finalize
		triggerFinalization = !auction.finalized;

		emit ClaimedLot(auction.lot, _user, _userRune, userShareOfLot, auction.rewards.tokens, auction.rewards.nfts);
	}

	function getProfitDistributions(
		uint256 _lot,
		uint256 _amount
	) public view onlyAuctioneer validAuctionLot(_lot) returns (uint256 treasuryDistribution, uint256 farmDistribution) {
		return auctions[_lot].getProfitDistributions(_amount, treasurySplit);
	}

	// FINALIZE

	function finalizeAuction(
		uint256 _lot
	)
		public
		onlyAuctioneer
		validAuctionLot(_lot)
		returns (
			bool triggerCancellation,
			uint256 treasuryEmissions,
			uint256 treasuryETHDistribution,
			uint256 farmETHDistribution
		)
	{
		Auction storage auction = auctions[_lot];

		// Exit if already finalized
		if (auction.finalized) return (false, 0, 0, 0);

		auction.validateEnded();

		// FALLBACK: cancel auction instead of finalizing if auction has 0 bids
		if (auction.bidData.bids == 0) return (true, 0, 0, 0);
		triggerCancellation = false;

		// Distribute lot revenue to treasury and farm
		(treasuryETHDistribution, farmETHDistribution) = auction.getRevenueDistributions(treasurySplit);

		// Send marked emissions to treasury
		treasuryEmissions = auction.emissions.treasuryEmission;

		// Mark Finalized
		auction.finalized = true;

		emit AuctionFinalized(auction.lot);
	}

	// HARVEST

	function validateAndGetHarvestData(
		uint256 _lot
	) public view validAuctionLot(_lot) returns (uint256 unlockTimestamp, uint256 bids, uint256 biddersEmissions) {
		auctions[_lot].validateEnded();
		unlockTimestamp = auctions[_lot].day * 1 days;
		bids = auctions[_lot].bidData.bids;
		biddersEmissions = auctions[_lot].emissions.biddersEmission;
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

	function getDailyAuctions(
		uint256 lookBackDays,
		uint256 lookForwardDays
	) public view returns (DailyAuctions[] memory data) {
		uint256 currentDay = block.timestamp / 1 days;
		uint256[] memory dayLots;
		uint256 day = currentDay - lookBackDays;
		data = new DailyAuctions[](lookBackDays + 1 + lookForwardDays);
		for (uint256 dayIndex = 0; dayIndex < (lookBackDays + 1 + lookForwardDays); dayIndex++) {
			dayLots = auctionsOnDay[day].values();
			data[dayIndex].day = day;
			data[dayIndex].lots = new uint256[](dayLots.length);

			for (uint256 dayLotIndex = 0; dayLotIndex < dayLots.length; dayLotIndex++) {
				data[dayIndex].lots[dayLotIndex] = dayLots[dayLotIndex];
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

	function getAuctionExts(
		uint256[] memory _lots
	) public view returns (Auction[] memory auctionBases, AuctionExt[] memory auctionExts) {
		auctionBases = new Auction[](_lots.length);
		auctionExts = new AuctionExt[](_lots.length);

		uint256 lot;
		for (uint256 i = 0; i < _lots.length; i++) {
			lot = _lots[i];
			auctionBases[i] = auctions[lot];
			auctionExts[i] = AuctionExt({
				lot: lot,
				blockTimestamp: block.timestamp,
				activeWindow: auctions[lot].activeWindow(),
				isBiddingOpen: auctions[lot].isBiddingOpen(),
				isEnded: auctions[lot].isEnded()
			});
		}
	}
}
