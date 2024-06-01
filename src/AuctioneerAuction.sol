// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Auction, AuctionParams, PaymentType, AuctioneerEvents, DailyAuctions, AuctionExt, NotAuctioneer, InvalidAuctionLot, InvalidRune, AuctionEnded, TooSteep, Invalid, PrivateAuction, TooManyAuctionsPerDay, InvalidDailyEmissionBP, NotCancellable } from "./IAuctioneer.sol";
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
// -- ARCH --

interface IAuctioneerAuction {
	function runeSwitchPenalty() external view returns (uint256);
	function runicLastBidderBonus() external view returns (uint256);
	function updateTreasury(address _treasury) external;
	function updateTeamTreasury(address _teamTreasury) external;
	function privateAuctionRequirement() external view returns (uint256);
	function createAuction(AuctionParams memory _params, uint256 _emissions) external payable returns (uint256 lot);
	function cancelAuction(uint256 _lot) external returns (uint256 unlockTimestamp, uint256 cancelledEmissions);
	struct BidData {
		address user;
		uint8 prevRune;
		uint8 newRune;
		uint256 existingBidCount;
		uint256 arrivingBidCount;
		PaymentType paymentType;
		uint256 userGoBalance;
	}
	function bid(
		uint256 _lot,
		BidData memory _data
	) external returns (uint256 userBidsAfterPenalty, uint256 bid, uint256 bidCost);
	function selectRune(
		uint256 _lot,
		uint256 _userBids,
		uint8 _prevRune,
		uint8 _rune,
		uint256
	) external returns (uint256);
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

	address public auctioneer;
	address public treasury;
	address public teamTreasury;
	uint256 public teamTreasurySplit = 2000;
	address public deadAddress = 0x000000000000000000000000000000000000dEaD;

	uint256 public lotCount;
	mapping(uint256 => Auction) public auctions;
	mapping(uint256 => EnumerableSet.UintSet) private auctionsOnDay;
	mapping(uint256 => uint256) public dailyCumulativeEmissionBP;

	uint256 public bidIncrement;
	uint256 public startingBid;
	uint256 public bidCost;
	uint256 public runeSwitchPenalty = 2000;
	uint256 public onceTwiceBlastBonusTime = 9;
	uint256 public privateAuctionRequirement;
	uint256 public runicLastBidderBonus = 2000;

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	receive() external payable {}

	function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
		return this.onERC721Received.selector;
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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

	modifier privateAuctionEligible(uint256 _lot, uint256 _goBalance) {
		if (auctions[_lot].isPrivate && _goBalance < privateAuctionRequirement) revert PrivateAuction();
		_;
	}
	function validateAuctionRunning(uint256 _lot) external view validAuctionLot(_lot) {
		if (auctions[_lot].isEnded()) revert AuctionEnded();
	}

	function validatePrivateAuctionEligibility(
		uint256 _lot,
		uint256 _goBalance
	) external view validAuctionLot(_lot) privateAuctionEligible(_lot, _goBalance) {}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function initializeBlast() external onlyOwner {
		_initializeBlast();
	}

	function claimYieldAll(address _recipient, uint256 _minClaimRateBips) external onlyOwner {
		_claimYieldAll(_recipient, _minClaimRateBips);
	}

	function updateTreasury(address _treasury) external onlyAuctioneer {
		treasury = _treasury;
	}

	function updateTeamTreasury(address _teamTreasury) external onlyAuctioneer {
		teamTreasury = _teamTreasury;
	}

	function updateTeamTreasurySplit(uint256 _teamTreasurySplit) external onlyOwner {
		if (_teamTreasurySplit > 5000) revert TooSteep();

		teamTreasurySplit = _teamTreasurySplit;
		emit UpdatedTeamTreasurySplit(_teamTreasurySplit);
	}

	function updateStartingBid(uint256 _startingBid) external onlyOwner {
		if (_startingBid == 0) revert Invalid();
		if (_startingBid > 0.1e18) revert Invalid();

		startingBid = _startingBid;
		emit UpdatedStartingBid(_startingBid);
	}

	function updateBidCost(uint256 _bidCost) external onlyOwner {
		if (_bidCost == 0) revert Invalid();
		if (_bidCost > 0.1e18) revert Invalid();

		bidCost = _bidCost;
		emit UpdatedBidCost(_bidCost);
	}

	function updatePrivateAuctionRequirement(uint256 _requirement) external onlyOwner {
		privateAuctionRequirement = _requirement;
		emit UpdatedPrivateAuctionRequirement(_requirement);
	}

	function updateRuneSwitchPenalty(uint256 _penalty) external onlyOwner {
		if (_penalty > 10000) revert Invalid();

		runeSwitchPenalty = _penalty;
		emit UpdatedRuneSwitchPenalty(_penalty);
	}

	function updateRunicLastBidderBonus(uint256 _bonus) external onlyOwner {
		if (_bonus > 5000) revert Invalid();

		runicLastBidderBonus = _bonus;
		emit UpdatedRunicLastBidderBonus(_bonus);
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function createAuction(
		AuctionParams memory _params,
		uint256 _allocatedEmissions
	) external payable onlyAuctioneer returns (uint256 lot) {
		_params.validate();

		lot = lotCount;
		uint256 day = _params.unlockTimestamp / 1 days;

		auctionsOnDay[day].add(lot);
		if (auctionsOnDay[day].length() > 4) revert TooManyAuctionsPerDay();

		dailyCumulativeEmissionBP[day] += _params.emissionBP;
		if (dailyCumulativeEmissionBP[day] > 40000) revert InvalidDailyEmissionBP();

		Auction storage auction = auctions[lotCount];

		auction.lot = lotCount;
		auction.day = day;
		auction.name = _params.name;
		auction.isPrivate = _params.isPrivate;
		auction.finalized = false;
		auction.initialBlock = block.number;

		auction.addRunes(_params);

		auction.unlockTimestamp = _params.unlockTimestamp;
		auction.addBidWindows(_params, onceTwiceBlastBonusTime);

		auction.addRewards(_params);
		auction.transferLotFrom(treasury);

		auction.emissions.bp = _params.emissionBP;
		auction.emissions.biddersEmission = _allocatedEmissions.scaleByBP(9000);
		auction.emissions.treasuryEmission = _allocatedEmissions.scaleByBP(1000);

		auction.bidData.revenue = 0;
		auction.bidData.bids = 0;
		auction.bidData.bid = startingBid;
		auction.bidData.bidTimestamp = _params.unlockTimestamp;
		auction.bidData.nextBidBy = auction.getNextBidBy();
		auction.bidData.bidCost = bidCost;

		lotCount++;
	}

	function cancelAuction(
		uint256 _lot
	) external onlyAuctioneer validAuctionLot(_lot) returns (uint256 unlockTimestamp, uint256 cancelledEmissions) {
		Auction storage auction = auctions[_lot];

		if (auction.bidData.bids > 0 || auction.finalized) revert NotCancellable();

		auction.transferLotTo(treasury, 1e18);
		auctionsOnDay[auction.day].remove(_lot);
		dailyCumulativeEmissionBP[auction.day] -= auction.emissions.bp;

		unlockTimestamp = auction.unlockTimestamp;
		cancelledEmissions = auction.emissions.biddersEmission + auction.emissions.treasuryEmission;

		auction.emissions.bp = 0;
		auction.emissions.biddersEmission = 0;
		auction.emissions.treasuryEmission = 0;
		auction.finalized = true;
	}

	function bid(
		uint256 _lot,
		BidData memory _data
	)
		external
		onlyAuctioneer
		validAuctionLot(_lot)
		validRune(_lot, _data.newRune)
		privateAuctionEligible(_lot, _data.userGoBalance)
		returns (uint256 userBidsAfterPenalty, uint256 auctionBid, uint256 auctionBidCost)
	{
		Auction storage auction = auctions[_lot];

		auction.validateBiddingOpen();

		auction.bidData.bid += bidIncrement * _data.arrivingBidCount;
		auction.bidData.bids += _data.arrivingBidCount;
		auction.bidData.bidUser = _data.user;
		auction.bidData.bidTimestamp = block.timestamp;
		auction.bidData.nextBidBy = auction.getNextBidBy();

		if (_data.paymentType != PaymentType.VOUCHER) {
			auction.bidData.revenue += auction.bidData.bidCost * _data.arrivingBidCount;
		}

		if (auction.runes.length > 0) {
			auction.runes[_data.newRune].bids += _data.arrivingBidCount;
			auction.bidData.bidRune = _data.newRune;
		}

		auctionBid = auction.bidData.bid;
		auctionBidCost = auction.bidData.bidCost;
		userBidsAfterPenalty = _switchRuneUpdateData(_lot, _data.existingBidCount, _data.prevRune, _data.newRune);
	}

	function selectRune(
		uint256 _lot,
		uint256 _userBids,
		uint8 _prevRune,
		uint8 _newRune,
		uint256 _userGoBalance
	)
		external
		onlyAuctioneer
		validAuctionLot(_lot)
		validRune(_lot, _newRune)
		privateAuctionEligible(_lot, _userGoBalance)
		returns (uint256 userBidsAfterPenalty)
	{
		if (auctions[_lot].isEnded()) revert AuctionEnded();
		if (auctions[_lot].runes.length == 0) revert InvalidRune();

		userBidsAfterPenalty = _switchRuneUpdateData(_lot, _userBids, _prevRune, _newRune);
	}

	function claimLot(
		uint256 _lot,
		address _user,
		uint256 _userBids,
		uint8 _userRune
	) external onlyAuctioneer validAuctionLot(_lot) returns (uint256 userShareOfPayment, bool triggerFinalization) {
		Auction storage auction = auctions[_lot];

		auction.validateEnded();
		auction.validateWinner(_user, _userRune);

		bool auctionHasRunes = auction.runes.length > 0;
		bool isLastBidder = auction.bidData.bidUser == _user;
		uint256 userShareOfLot = 1e18;

		if (auctionHasRunes) {
			uint256 lastBidderBonusBids = isLastBidder
				? auction.runes[_userRune].bids.scaleByBP(runicLastBidderBonus)
				: 0;

			userShareOfLot =
				((_userBids + lastBidderBonusBids) * 1e18) /
				auction.runes[_userRune].bids.scaleByBP(10000 + runicLastBidderBonus);
		}

		auction.transferLotTo(_user, userShareOfLot);

		userShareOfPayment = (auction.bidData.bid * userShareOfLot) / 1e18;
		triggerFinalization = !auction.finalized;
	}

	function finalizeAuction(
		uint256 _lot
	)
		external
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
		if (auctions[_lot].finalized) return (false, 0, 0, 0, 0);

		Auction storage auction = auctions[_lot];
		auction.validateEnded();

		// If auction ends with 0 bids, cancel it to recover the lot
		if (auction.bidData.bids == 0) return (true, 0, 0, 0, 0);

		auction.finalized = true;

		triggerCancellation = false;
		treasuryEmissions = auction.emissions.treasuryEmission;
		(treasuryETHDistribution, farmETHDistribution, teamTreasuryETHDistribution) = auction.getRevenueDistributions(
			teamTreasurySplit
		);

		emit AuctionFinalized(auction.lot);
	}

	function validateAndGetHarvestData(
		uint256 _lot
	) external view validAuctionLot(_lot) returns (uint256 unlockTimestamp, uint256 bids, uint256 biddersEmissions) {
		auctions[_lot].validateEnded();
		unlockTimestamp = auctions[_lot].day * 1 days;
		bids = auctions[_lot].bidData.bids;
		biddersEmissions = auctions[_lot].emissions.biddersEmission;
	}

	function getProfitDistributions(
		uint256 _lot,
		uint256 _amount
	)
		external
		view
		onlyAuctioneer
		validAuctionLot(_lot)
		returns (uint256 farmDistribution, uint256 teamTreasuryDistribution)
	{
		return auctions[_lot].getProfitDistributions(_amount, teamTreasurySplit);
	}

	function _switchRuneUpdateData(
		uint256 _lot,
		uint256 _userBids,
		uint8 _prevRune,
		uint8 _newRune
	) internal returns (uint256 userBidsAfterPenalty) {
		if (_userBids == 0) return _userBids;
		if (_prevRune == _newRune) return _userBids;

		userBidsAfterPenalty = _userBids < 4 ? _userBids : _userBids.scaleByBP(10000 - runeSwitchPenalty);

		auctions[_lot].runes[_newRune].bids += userBidsAfterPenalty;
		auctions[_lot].bidData.bids = auctions[_lot].bidData.bids + userBidsAfterPenalty - _userBids;
		if (_prevRune != 0) {
			auctions[_lot].runes[_prevRune].bids -= _userBids;
		}
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function getAuction(uint256 _lot) external view validAuctionLot(_lot) returns (Auction memory) {
		return auctions[_lot];
	}

	function getAuctionsPerDay(uint256 _day) external view returns (uint256) {
		return auctionsOnDay[_day].values().length;
	}

	function getAuctionsOnDay(uint256 _day) external view returns (uint256[] memory) {
		return auctionsOnDay[_day].values();
	}

	function getDailyAuctions(
		uint256 lookBackDays,
		uint256 lookForwardDays
	) external view returns (DailyAuctions[] memory data) {
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
	) external view validAuctionLot(_lot) returns (Auction memory auction, AuctionExt memory ext) {
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
	) external view returns (Auction[] memory auctionBases, AuctionExt[] memory auctionExts) {
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
