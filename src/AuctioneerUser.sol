// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { Auctioneer } from "./Auctioneer.sol";
import "./IAuctioneer.sol";
import { GBMath } from "./AuctionUtils.sol";
import { IAuctioneerEmissions } from "./AuctioneerEmissions.sol";
import { IAuctioneerAuction } from "./AuctioneerAuction.sol";

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

interface IAuctioneerUser {
	function link(address _auctioneerEmissions, address _auctioneerAuction) external;
	function bid(
		uint256 _lot,
		address _user,
		BidOptions memory _options
	) external returns (uint256 prevUserBids, uint8 prevRune, string memory userAlias);
	function selectRune(uint256 _lot, address _user, uint8 _rune) external returns (uint256 userBids, uint8 prevRune);
	function claimLot(uint256 _lot, address _user) external returns (uint8 rune, uint256 bids);
	function harvestAuctionEmissions(
		uint256 _lot,
		address _user,
		uint256 _unlockTimestamp,
		uint256 _auctionBids,
		uint256 _biddersEmission,
		bool _harvestToFarm
	) external returns (uint256 harvested, uint256 burned);
	function markAuctionHarvestable(uint256 _lot, address _user) external;
}

contract AuctioneerUser is IAuctioneerUser, Ownable, ReentrancyGuard, AuctioneerEvents {
	using GBMath for uint256;
	using SafeERC20 for IERC20;
	using EnumerableSet for EnumerableSet.UintSet;

	address payable public auctioneer;
	IAuctioneerEmissions public auctioneerEmissions;
	IAuctioneerAuction public auctioneerAuction;
	bool public linked;

	// AUCTION USER
	mapping(uint256 => mapping(address => AuctionUser)) public auctionUsers;
	mapping(address => EnumerableSet.UintSet) internal userInteractedLots;
	mapping(address => EnumerableSet.UintSet) internal userUnharvestedLots;
	mapping(address => string) public userAlias;
	mapping(string => address) public aliasUser;

	constructor() Ownable(msg.sender) {}

	function link(address _auctioneerEmissions, address _auctioneerAuction) public {
		if (linked) revert AlreadyLinked();
		linked = true;

		auctioneer = payable(msg.sender);
		auctioneerEmissions = IAuctioneerEmissions(_auctioneerEmissions);
		auctioneerAuction = IAuctioneerAuction(_auctioneerAuction);
	}

	///////////////////
	// MODIFIERS
	///////////////////

	modifier onlyAuctioneer() {
		if (msg.sender != auctioneer) revert NotAuctioneer();
		_;
	}

	///////////////////
	// BID
	///////////////////

	function bid(
		uint256 _lot,
		address _user,
		BidOptions memory _options
	) public onlyAuctioneer returns (uint256 prevUserBids, uint8 prevRune, string memory userAliasRet) {
		AuctionUser storage user = auctionUsers[_lot][_user];
		prevUserBids = user.bids;
		prevRune = user.rune;
		userAliasRet = userAlias[_user];

		// Force bid count to be at least one
		if (_options.multibid == 0) _options.multibid = 1;

		// Incur rune switch penalty
		if (user.rune != _options.rune && user.rune != 0) {
			user.bids = user.bids.scaleByBP(10000 - auctioneerAuction.runeSwitchPenalty());
		}

		// Mark users bids
		user.bids += _options.multibid;

		// Mark users rune
		if (user.rune != _options.rune) {
			user.rune = _options.rune;
		}

		// Mark user has interacted with this lot
		userInteractedLots[_user].add(_lot);
	}

	function markAuctionHarvestable(uint256 _lot, address _user) public onlyAuctioneer {
		userUnharvestedLots[_user].add(_lot);
	}

	function selectRune(
		uint256 _lot,
		address _user,
		uint8 _rune
	) public onlyAuctioneer returns (uint256 userBids, uint8 prevRune) {
		AuctionUser storage user = auctionUsers[_lot][_user];
		userBids = user.bids;
		prevRune = user.rune;
		user.rune = _rune;

		// Incur rune switch penalty
		if (prevRune != _rune) {
			user.bids = user.bids.scaleByBP(10000 - auctioneerAuction.runeSwitchPenalty());
		}
	}

	///////////////////
	// CLAIM
	///////////////////

	function claimLot(uint256 _lot, address _user) public onlyAuctioneer returns (uint8 rune, uint256 bids) {
		AuctionUser storage user = auctionUsers[_lot][_user];

		// Winner has already paid for and claimed the lot (or their share of it)
		if (user.lotClaimed) revert UserAlreadyClaimedLot();

		// Mark lot as claimed
		user.lotClaimed = true;

		// Return values
		rune = user.rune;
		bids = user.bids;
	}

	///////////////////
	// HARVEST
	///////////////////

	function harvestAuctionEmissions(
		uint256 _lot,
		address _user,
		uint256 _unlockTimestamp,
		uint256 _auctionBids,
		uint256 _biddersEmission,
		bool _harvestToFarm
	) public onlyAuctioneer returns (uint256 harvested, uint256 burned) {
		AuctionUser storage user = auctionUsers[_lot][_user];

		// Exit if user already harvested emissions from auction
		if (user.emissionsHarvested) return (0, 0);

		// Exit early if nothing to claim
		if (user.bids == 0) return (0, 0);

		// Mark harvested
		user.emissionsHarvested = true;
		userUnharvestedLots[_user].remove(_lot);

		// Signal auctioneerEmissions to harvest user's emissions
		(harvested, burned) = auctioneerEmissions.harvestEmissions(
			_user,
			(_biddersEmission * user.bids) / _auctionBids,
			_unlockTimestamp,
			_harvestToFarm
		);

		user.harvestedEmissions = harvested;
		user.burnedEmissions = burned;
	}

	///////////////////
	// ALIAS
	///////////////////

	function setAlias(string memory _alias) public nonReentrant {
		if (bytes(_alias).length < 3 || bytes(_alias).length > 9) revert InvalidAlias();
		if (aliasUser[_alias] != address(0)) revert AliasTaken();

		// Clear out old alias if it exists
		if (bytes(userAlias[msg.sender]).length != 0) {
			aliasUser[userAlias[msg.sender]] = address(0);
		}

		userAlias[msg.sender] = _alias;
		aliasUser[_alias] = msg.sender;

		emit UpdatedAlias(msg.sender, _alias);
	}

	///////////////////
	// VIEW
	///////////////////

	function getAuctionUser(uint256 _lot, address _user) public view returns (AuctionUser memory) {
		return auctionUsers[_lot][_user];
	}

	function getUserInteractedLots(address _user) public view returns (uint256[] memory) {
		return userInteractedLots[_user].values();
	}

	function getUserUnharvestedLots(address _user) public view returns (uint256[] memory) {
		return userUnharvestedLots[_user].values();
	}

	function getUserLotInfos(uint256[] memory _lots, address _user) public view returns (UserLotInfo[] memory infos) {
		infos = new UserLotInfo[](_lots.length);

		uint256 lot;
		for (uint256 i = 0; i < _lots.length; i++) {
			lot = _lots[i];
			Auction memory auction = auctioneerAuction.getAuction(lot);
			uint256 runicLastBidderBonus = auctioneerAuction.runicLastBidderBonus();
			AuctionUser memory user = auctionUsers[lot][_user];
			bool auctionHasRunes = auction.runes.length > 0;
			bool auctionHasBids = auction.bidData.bids > 0;

			infos[i].lot = auction.lot;
			infos[i].rune = user.rune;

			// Bids
			infos[i].bidCounts.user = user.bids;
			infos[i].bidCounts.rune = !auctionHasRunes || user.rune == 0 ? 0 : auction.runes[user.rune].bids;
			infos[i].bidCounts.auction = auction.bidData.bids;

			// Emissions
			infos[i].matureTimestamp = (auction.day * 1 days) + auctioneerEmissions.emissionTaxDuration();
			infos[i].timeUntilMature = block.timestamp >= infos[i].matureTimestamp
				? 0
				: infos[i].matureTimestamp - block.timestamp;
			infos[i].emissionsEarned = user.bids == 0 || auction.bidData.bids == 0
				? 0
				: (user.bids * auction.emissions.biddersEmission) / auction.bidData.bids;

			infos[i].emissionsHarvested = user.emissionsHarvested;
			infos[i].harvestedEmissions = user.harvestedEmissions;
			infos[i].burnedEmissions = user.burnedEmissions;

			// Winning bid
			infos[i].isWinner =
				user.bids > 0 &&
				(auction.runes.length > 0 ? user.rune == auction.bidData.bidRune : _user == auction.bidData.bidUser);
			infos[i].lotClaimed = user.lotClaimed;

			// Share
			bool isLastBidder = auction.bidData.bidUser == _user;
			uint256 runicLastBidderBonusBids = isLastBidder && auctionHasRunes
				? auction.runes[user.rune].bids.scaleByBP(runicLastBidderBonus)
				: 0;

			infos[i].shareOfLot = auctionHasBids
				? (
					auctionHasRunes
						? ((user.bids + runicLastBidderBonusBids) * 1e18) /
							auction.runes[user.rune].bids.scaleByBP(10000 + runicLastBidderBonus)
						: 1e18
				)
				: 0;
			infos[i].price = (auction.bidData.bid * infos[i].shareOfLot) / 1e18;
		}
	}
}
