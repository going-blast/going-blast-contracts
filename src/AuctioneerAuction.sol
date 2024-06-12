// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Auction, AuctionParams, PaymentType, AuctioneerEvents, AuctionExt, NotAuctioneer, InvalidAuctionLot, InvalidRune, AuctionEnded, Invalid, NotCancellable, Unauthorized } from "./IAuctioneer.sol";
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
	function createAuction(
		address _creator,
		AuctionParams memory _params,
		uint256 _treasuryCut
	) external payable returns (uint256 lot);
	function cancelAuction(address _creator, uint256 _lot, bool _isAdmin) external;
	struct BidData {
		address user;
		uint8 prevRune;
		uint8 newRune;
		uint256 existingBidCount;
		uint256 arrivingBidCount;
		PaymentType paymentType;
	}
	function bid(
		uint256 _lot,
		BidData memory _data
	) external returns (uint256 userBidsAfterPenalty, uint256 bid, uint256 bidCost);
	function selectRune(uint256 _lot, uint256 _userBids, uint8 _prevRune, uint8 _rune) external returns (uint256);
	function claimLot(
		uint256 _lot,
		address _user,
		uint256 _userBids,
		uint8 _userRune
	) external returns (uint256 userShareOfPayment, address creator, uint256 treasuryCut, bool triggerFinalization);
	function finalizeAuction(
		uint256 _lot
	) external returns (bool triggerCancellation, uint256 revenue, address creator, uint256 treasuryCut);
	function validateAuctionRunning(uint256 _lot) external view;
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
	address public deadAddress = 0x000000000000000000000000000000000000dEaD;

	uint256 public lotCount;
	mapping(uint256 => Auction) public auctions;

	uint256 public runeSwitchPenalty = 2000;
	uint256 public onceTwiceBlastBonusTime = 9;
	uint256 public runicLastBidderBonus = 2000;

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	constructor(address _auctioneer) Ownable(msg.sender) {
		auctioneer = _auctioneer;
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

	function validateAuctionRunning(uint256 _lot) external view validAuctionLot(_lot) {
		if (auctions[_lot].isEnded()) revert AuctionEnded();
	}

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
		address _creator,
		AuctionParams memory _params,
		uint256 _treasuryCut
	) external payable onlyAuctioneer returns (uint256 lot) {
		_params.validate();

		lot = lotCount;
		uint256 day = _params.unlockTimestamp / 1 days;

		Auction storage auction = auctions[lotCount];

		auction.creator = _creator;
		auction.lot = lotCount;
		auction.day = day;
		auction.name = _params.name;
		auction.treasuryCut = _treasuryCut;
		auction.finalized = false;
		auction.initialBlock = block.number;

		auction.addRunes(_params);

		auction.unlockTimestamp = _params.unlockTimestamp;
		auction.addBidWindows(_params, onceTwiceBlastBonusTime);

		auction.addRewards(_params);
		auction.transferLotFrom(_creator);

		auction.bidData.revenue = 0;
		auction.bidData.bids = 0;
		auction.bidData.bid = _params.startingBid;
		auction.bidData.bidTimestamp = _params.unlockTimestamp;
		auction.bidData.nextBidBy = auction.getNextBidBy();
		auction.bidData.bidCost = _params.bidCost;
		auction.bidData.bidIncrement = _params.bidIncrement;

		lotCount++;
	}

	function cancelAuction(
		address _canceller,
		uint256 _lot,
		bool _isAdmin
	) external onlyAuctioneer validAuctionLot(_lot) {
		Auction storage auction = auctions[_lot];

		if (!_isAdmin && auction.creator != _canceller) revert Unauthorized();
		if (auction.bidData.bids > 0 || auction.finalized) revert NotCancellable();

		auction.transferLotTo(auction.creator, 1e18);

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
		returns (uint256 userBidsAfterPenalty, uint256 auctionBid, uint256 auctionBidCost)
	{
		Auction storage auction = auctions[_lot];

		auction.validateBiddingOpen();

		auction.bidData.bid += auction.bidData.bidIncrement * _data.arrivingBidCount;
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
		uint8 _newRune
	) external onlyAuctioneer validAuctionLot(_lot) validRune(_lot, _newRune) returns (uint256 userBidsAfterPenalty) {
		if (auctions[_lot].isEnded()) revert AuctionEnded();
		if (auctions[_lot].runes.length == 0) revert InvalidRune();

		userBidsAfterPenalty = _switchRuneUpdateData(_lot, _userBids, _prevRune, _newRune);
	}

	function claimLot(
		uint256 _lot,
		address _user,
		uint256 _userBids,
		uint8 _userRune
	)
		external
		onlyAuctioneer
		validAuctionLot(_lot)
		returns (uint256 userShareOfPayment, address creator, uint256 treasuryCut, bool triggerFinalization)
	{
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
		creator = auction.creator;
		treasuryCut = auction.treasuryCut;
		triggerFinalization = !auction.finalized;
	}

	function finalizeAuction(
		uint256 _lot
	)
		external
		onlyAuctioneer
		validAuctionLot(_lot)
		returns (bool triggerCancellation, uint256 revenue, address creator, uint256 treasuryCut)
	{
		if (auctions[_lot].finalized) return (false, 0, auctions[_lot].creator, 0);

		Auction storage auction = auctions[_lot];
		auction.validateEnded();

		// If auction ends with 0 bids, cancel it to recover the lot
		if (auction.bidData.bids == 0) return (true, 0, auctions[_lot].creator, 0);

		auction.finalized = true;

		revenue = auction.bidData.revenue;
		creator = auction.creator;
		treasuryCut = auction.treasuryCut;
		triggerCancellation = false;

		emit AuctionFinalized(auction.lot);
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

	// TODO: Get live auctions

	// function getDailyAuctions(
	// 	uint256 lookBackDays,
	// 	uint256 lookForwardDays
	// ) external view returns (DailyAuctions[] memory data) {
	// 	uint256 currentDay = block.timestamp / 1 days;
	// 	uint256[] memory dayLots;
	// 	uint256 day = currentDay - lookBackDays;
	// 	data = new DailyAuctions[](lookBackDays + 1 + lookForwardDays);
	// 	for (uint256 dayIndex = 0; dayIndex < (lookBackDays + 1 + lookForwardDays); dayIndex++) {
	// 		dayLots = auctionsOnDay[day].values();
	// 		data[dayIndex].day = day;
	// 		data[dayIndex].lots = new uint256[](dayLots.length);

	// 		for (uint256 dayLotIndex = 0; dayLotIndex < dayLots.length; dayLotIndex++) {
	// 			data[dayIndex].lots[dayLotIndex] = dayLots[dayLotIndex];
	// 		}
	// 		day++;
	// 	}
	// }

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
