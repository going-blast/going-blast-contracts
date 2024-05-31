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
	function runeSwitchPenalty() external view returns (uint256);
	function runicLastBidderBonus() external view returns (uint256);
	function updateTreasury(address _treasury) external;
	function updateTeamTreasury(address _teamTreasury) external;
	function privateAuctionRequirement() external view returns (uint256);
	function createAuction(AuctionParams memory _params, uint256 _emissions) external payable returns (uint256 lot);
	function cancelAuction(uint256 _lot) external returns (uint256 unlockTimestamp, uint256 cancelledEmissions);
	struct MarkBidPayload {
		address user;
		uint8 prevRune;
		uint8 newRune;
		uint256 existingBidCount;
		uint256 arrivingBidCount;
		PaymentType paymentType;
		uint256 userGoBalance;
	}
	function markBid(
		uint256 _lot,
		MarkBidPayload memory _payload
	) external returns (uint256 userBidsAfterPenalty, uint256 bid, uint256 bidCost);
	function selectRune(uint256 _lot, uint256 _userBids, uint8 _prevRune, uint8 _rune) external returns (uint256);
	function claimLot(
		uint256 _lot,
		address _user,
		uint256 _userBids,
		uint8 _userRune
	) external returns (uint256 userShareOfPayment, bool triggerFinalization);
	function finalizeAuction(
		uint256 _lot
	)
		external
		returns (
			bool triggerCancellation,
			uint256 treasuryEmissions,
			uint256 treasuryETHDistribution,
			uint256 farmETHDistribution,
			uint256 teamTreasuryDistribution
		);
	function getProfitDistributions(
		uint256 _lot,
		uint256 _amount
	) external view returns (uint256 farmDistribution, uint256 teamTreasuryDistribution);
	function validateAndGetHarvestData(
		uint256 _lot
	) external view returns (uint256 unlockTimestamp, uint256 bids, uint256 biddersEmissions);
	function validateAuctionRunning(uint256 _lot) external view;
	function validatePrivateAuctionEligibility(uint256 _lot, uint256 _goBalance) external view;
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
	address public auctioneer;
	address public treasury;
	address public teamTreasury;
	uint256 public teamTreasurySplit = 2000;
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
		address _auctioneer,
		uint256 _bidCost,
		uint256 _bidIncrement,
		uint256 _startingBid,
		uint256 _privateAuctionRequirement
	) Ownable(msg.sender) {
		auctioneer = _auctioneer;
		bidCost = _bidCost;
		bidIncrement = _bidIncrement;
		startingBid = _startingBid;
		privateAuctionRequirement = _privateAuctionRequirement;
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
		if (auctions[_lot].runes.length > 0 && (_rune == 0 || _rune >= auctions[_lot].runes.length))
			revert InvalidRune();
		if (auctions[_lot].runes.length == 0 && _rune != 0) revert InvalidRune();
		_;
	}

	// EXTERNAL MODIFIERS

	function validateAuctionEnded(uint256 _lot) public view validAuctionLot(_lot) {
		auctions[_lot].validateEnded();
	}
	function validateAuctionRunning(uint256 _lot) public view validAuctionLot(_lot) {
		if (auctions[_lot].isEnded()) revert AuctionEnded();
	}
	function validatePrivateAuctionEligibility(uint256 _lot, uint256 _goBalance) public view validAuctionLot(_lot) {
		if (auctions[_lot].isPrivate && _goBalance < privateAuctionRequirement) revert PrivateAuction();
	}

	// Admin

	function updateTreasury(address _treasury) public onlyAuctioneer {
		treasury = _treasury;
	}
	function updateTeamTreasury(address _teamTreasury) public onlyAuctioneer {
		teamTreasury = _teamTreasury;
	}

	function updateTeamTreasurySplit(uint256 _teamTreasurySplit) public onlyOwner {
		if (_teamTreasurySplit > 5000) revert TooSteep();
		teamTreasurySplit = _teamTreasurySplit;
		emit UpdatedTeamTreasurySplit(_teamTreasurySplit);
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

		auction.initialBlock = block.number;

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

	function _switchRuneUpdateData(
		uint256 _lot,
		uint256 _userBids,
		uint8 _prevRune,
		uint8 _newRune
	) internal returns (uint256 userBidsAfterPenalty) {
		// Exit if no rune switch
		if (_prevRune == _newRune) return _userBids;

		// Remove existing bids from users previous rune
		if (_prevRune != 0 && _userBids > 0) {
			auctions[_lot].runes[_prevRune].bids -= _userBids;
		}

		if (_userBids == 0) return _userBids;

		// Incur rune switch penalty and update state
		//	 errata: `user.bids < 4 ? user.bids ...` prevents kneecapping users that have 1 or 2 bids and lose 50% - 100% of them
		userBidsAfterPenalty = _userBids < 4 ? _userBids : _userBids.scaleByBP(10000 - runeSwitchPenalty);
		auctions[_lot].runes[_newRune].bids += userBidsAfterPenalty;
		auctions[_lot].bidData.bids = auctions[_lot].bidData.bids + userBidsAfterPenalty - _userBids;
	}

	function markBid(
		uint256 _lot,
		MarkBidPayload memory _payload
	)
		external
		onlyAuctioneer
		validAuctionLot(_lot)
		validRune(_lot, _payload.newRune)
		returns (uint256 userBidsAfterPenalty, uint256 bid, uint256 auctionBidCost)
	{
		Auction storage auction = auctions[_lot];
		auction.validateBiddingOpen();

		// VALIDATE: User can participate in auction
		if (auction.isPrivate && _payload.userGoBalance < privateAuctionRequirement) revert PrivateAuction();

		// Update auction with new bid
		auction.bidData.bid += bidIncrement * _payload.arrivingBidCount;
		auction.bidData.bids += _payload.arrivingBidCount;
		auction.bidData.bidUser = _payload.user;
		auction.bidData.bidTimestamp = block.timestamp;
		auction.bidData.nextBidBy = auction.getNextBidBy();

		if (_payload.paymentType != PaymentType.VOUCHER) {
			auction.bidData.revenue += auction.bidData.bidCost * _payload.arrivingBidCount;
		}

		// Runes
		if (auction.runes.length > 0) {
			auction.runes[_payload.newRune].bids += _payload.arrivingBidCount;
			auction.bidData.bidRune = _payload.newRune;
		}

		bid = auction.bidData.bid;
		auctionBidCost = auction.bidData.bidCost;
		userBidsAfterPenalty = _switchRuneUpdateData(
			_lot,
			_payload.existingBidCount,
			_payload.prevRune,
			_payload.newRune
		);
	}

	function selectRune(
		uint256 _lot,
		uint256 _userBids,
		uint8 _prevRune,
		uint8 _rune
	) external onlyAuctioneer validAuctionLot(_lot) validRune(_lot, _rune) returns (uint256 userBidsAfterPenalty) {
		if (auctions[_lot].isEnded()) revert AuctionEnded();
		if (auctions[_lot].runes.length == 0) revert InvalidRune();
		userBidsAfterPenalty = _switchRuneUpdateData(_lot, _userBids, _prevRune, _rune);
	}

	// CLAIM

	function claimLot(
		uint256 _lot,
		address _user,
		uint256 _userBids,
		uint8 _userRune
	) public onlyAuctioneer validAuctionLot(_lot) returns (uint256 userShareOfPayment, bool triggerFinalization) {
		Auction storage auction = auctions[_lot];

		auction.validateEnded();
		auction.validateWinner(_user, _userRune);

		// Calculate the user's share, dependent on rune / no rune
		bool auctionHasRunes = auction.runes.length > 0;
		bool isLastBidder = auction.bidData.bidUser == _user;
		uint256 runicLastBidderBonusBids = isLastBidder && auctionHasRunes
			? auction.runes[_userRune].bids.scaleByBP(runicLastBidderBonus)
			: 0;
		uint256 userShareOfLot = auctionHasRunes
			? ((_userBids + runicLastBidderBonusBids) * 1e18) /
				auction.runes[_userRune].bids.scaleByBP(10000 + runicLastBidderBonus)
			: 1e18;
		userShareOfPayment = (auction.bidData.bid * userShareOfLot) / 1e18;

		// Transfer lot to user
		auction.transferLotTo(_user, userShareOfLot);

		// Finalize
		triggerFinalization = !auction.finalized;
	}

	function getProfitDistributions(
		uint256 _lot,
		uint256 _amount
	)
		public
		view
		onlyAuctioneer
		validAuctionLot(_lot)
		returns (uint256 farmDistribution, uint256 teamTreasuryDistribution)
	{
		return auctions[_lot].getProfitDistributions(_amount, teamTreasurySplit);
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
			uint256 farmETHDistribution,
			uint256 teamTreasuryETHDistribution
		)
	{
		Auction storage auction = auctions[_lot];

		// Exit if already finalized
		if (auction.finalized) return (false, 0, 0, 0, 0);

		auction.validateEnded();

		// FALLBACK: cancel auction instead of finalizing if auction has 0 bids
		if (auction.bidData.bids == 0) return (true, 0, 0, 0, 0);
		triggerCancellation = false;

		// Distribute lot revenue to treasury, farm, and team treasury
		(treasuryETHDistribution, farmETHDistribution, teamTreasuryETHDistribution) = auction.getRevenueDistributions(
			teamTreasurySplit
		);

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
