// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAuctioneerFarm } from "./AuctioneerFarm.sol";
import { AuctioneerEvents, EpochData, EmissionsNotReceived, AlreadyInitialized, NotAuctioneer, Invalid } from "./IAuctioneer.sol";
import { GBMath } from "./AuctionUtils.sol";

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

interface IAuctioneerEmissions {
	function emissionTaxDuration() external view returns (uint256);
	function emissionsInitialized() external view returns (bool);

	function allocateAuctionEmissions(uint256 _unlockTimestamp, uint256 _bp) external returns (uint256 emissions);
	function deAllocateEmissions(uint256 _unlockTimestamp, uint256 _emissionsToDeAllocate) external;
	function transferEmissions(address _to, uint256 _amount) external;
	function harvestEmissions(
		address _user,
		uint256 _emissions,
		uint256 _emissionsEarnedTimestamp,
		bool _harvestToFarm
	) external returns (uint256 harvested, uint256 burned);
	function executeMigration(address _dest) external returns (uint256 unallocated);
}

// Emission handling
contract AuctioneerEmissions is IAuctioneerEmissions, Ownable, AuctioneerEvents {
	using GBMath for uint256;
	using SafeERC20 for IERC20;

	IERC20 public GO;
	address public auctioneer;
	address public deadAddress = 0x000000000000000000000000000000000000dEaD;

	uint256 public constant EPOCH_DURATION = 90;
	uint256 public constant EMISSION_PER_SHARE = 255e18;
	uint256 public constant EMISSION_SHARES_TOTAL = 255;
	uint256[8] public EMISSION_SHARES_PER_EPOCH = [128, 64, 32, 16, 8, 4, 2, 1];

	bool public emissionsInitialized = false;
	uint256 public earlyHarvestTax = 5000;
	uint256 public emissionTaxDuration = 30 days;
	uint256 public emissionsGenesisDay;
	uint256[8] public epochEmissionsRemaining = [0, 0, 0, 0, 0, 0, 0, 0];

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	constructor(address _auctioneer, IERC20 _go) Ownable(msg.sender) {
		auctioneer = _auctioneer;
		GO = _go;
	}

	function initializeEmissions(uint256 _unlockTimestamp) external onlyOwner {
		if (GO.balanceOf(address(this)) == 0) revert EmissionsNotReceived();
		if (emissionsInitialized) revert AlreadyInitialized();

		emissionsInitialized = true;
		emissionsGenesisDay = _unlockTimestamp / 1 days;

		uint256 totalToEmit = GO.balanceOf(address(this));
		for (uint8 i = 0; i < 8; i++) {
			epochEmissionsRemaining[i] = (totalToEmit * EMISSION_SHARES_PER_EPOCH[i]) / EMISSION_SHARES_TOTAL;
		}

		emit InitializedEmissions();
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	modifier onlyAuctioneer() {
		if (msg.sender != auctioneer) revert NotAuctioneer();
		_;
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function updateEarlyHarvestTax(uint256 _earlyHarvestTax) external onlyOwner {
		if (_earlyHarvestTax > 8000) revert Invalid();

		earlyHarvestTax = _earlyHarvestTax;
		emit UpdatedEarlyHarvestTax(_earlyHarvestTax);
	}

	function updateEmissionTaxDuration(uint256 _emissionTaxDuration) external onlyOwner {
		if (_emissionTaxDuration > 60 days) revert Invalid();

		emissionTaxDuration = _emissionTaxDuration;
		emit UpdatedEmissionTaxDuration(_emissionTaxDuration);
	}
	function executeMigration(address _dest) external onlyAuctioneer returns (uint256 unallocated) {
		for (uint8 i = 0; i < 8; i++) {
			unallocated += epochEmissionsRemaining[i];
		}

		GO.safeTransfer(_dest, unallocated);
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function allocateAuctionEmissions(
		uint256 _unlockTimestamp,
		uint256 _bp
	) external onlyAuctioneer returns (uint256 emissions) {
		uint256 day = _unlockTimestamp / 1 days;
		uint256 epoch = _getEpochAtDay(day);
		emissions = _getAuctionEmissionOnDay(day, _bp);
		epochEmissionsRemaining[epoch] -= emissions;
	}

	function deAllocateEmissions(uint256 _unlockTimestamp, uint256 _emissionsToDeAllocate) external onlyAuctioneer {
		uint256 epoch = _getEpochAtDay(_unlockTimestamp / 1 days);
		if (epoch < 8) {
			epochEmissionsRemaining[epoch] += _emissionsToDeAllocate;
		}
	}

	function harvestEmissions(
		address _user,
		uint256 _emissions,
		uint256 _emissionsEarnedTimestamp,
		bool _harvestToFarm
	) external onlyAuctioneer returns (uint256 harvested, uint256 burned) {
		bool incursTax = !_harvestToFarm && block.timestamp < (_emissionsEarnedTimestamp + emissionTaxDuration);

		harvested = _emissions.scaleByBP(incursTax ? (10000 - earlyHarvestTax) : 10000);
		burned = _emissions - harvested;

		_transferEmissions(_harvestToFarm ? auctioneer : _user, harvested);
		_transferEmissions(deadAddress, burned);
	}

	function transferEmissions(address _to, uint256 _amount) external onlyAuctioneer {
		_transferEmissions(_to, _amount);
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function _getEpochAtDay(uint256 day) internal view returns (uint256 epoch) {
		if (emissionsGenesisDay == 0 || day < emissionsGenesisDay) return 0;
		epoch = (day - emissionsGenesisDay) / EPOCH_DURATION;
	}

	function _getEpochDataAtDay(uint256 day) internal view returns (EpochData memory epochData) {
		epochData.epoch = _getEpochAtDay(day);

		epochData.start = emissionsGenesisDay + (epochData.epoch * EPOCH_DURATION);
		epochData.end = epochData.start + (EPOCH_DURATION);

		if (epochData.epoch >= 8) return epochData;

		epochData.emissionsRemaining = epochEmissionsRemaining[epochData.epoch];

		if (day > epochData.end) return epochData;

		uint256 daysElapsed = day - epochData.start;
		epochData.daysRemaining = daysElapsed > EPOCH_DURATION ? 0 : (EPOCH_DURATION - daysElapsed);

		if (epochData.daysRemaining == 0 || epochData.emissionsRemaining == 0) return epochData;

		epochData.dailyEmission = epochData.emissionsRemaining / epochData.daysRemaining;
	}

	// Maximum daily allowable emission bonus is 40000
	// Most days, the emission will be 10000
	// This allows us to scale up or down the number of auctions per week
	// An emission BP over 10000 means it is using emissions scheduled for other days
	// This will not overflow the epoch's emissions though, because the daily emission amount is calculated from remaining days
	function _getAuctionEmissionOnDay(uint256 day, uint256 _bp) internal view returns (uint256 emissions) {
		EpochData memory epochData = _getEpochDataAtDay(day);

		emissions = epochData.dailyEmission;
		if (emissions == 0) return emissions;

		emissions = emissions.scaleByBP(_bp);
		if (emissions <= epochData.emissionsRemaining) return emissions;

		emissions = epochData.emissionsRemaining;
	}

	function _transferEmissions(address _to, uint256 _amount) internal {
		if (_amount == 0) return;
		GO.safeTransfer(_to, _amount);
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function getAuctionEmission(uint256 _unlockTimestamp, uint256 _bp) external view returns (uint256 emissions) {
		return _getAuctionEmissionOnDay(_unlockTimestamp / 1 days, _bp);
	}

	function getEpochDataAtTimestamp(uint256 _timestamp) external view returns (EpochData memory epochData) {
		return _getEpochDataAtDay(_timestamp / 1 days);
	}

	function getCurrentEpochData() external view returns (uint256) {
		return _getEpochAtDay(block.timestamp / 1 days);
	}

	function getEmissionSharePerEpoch() external view returns (uint256[] memory shares) {
		shares = new uint256[](8);
		for (uint8 i = 0; i < 8; i++) {
			shares[i] = EMISSION_SHARES_PER_EPOCH[i];
		}
	}

	function getEpochEmissionsRemaining() external view returns (uint256[] memory emissionsRemaining) {
		emissionsRemaining = new uint256[](8);
		for (uint8 i = 0; i < 8; i++) {
			emissionsRemaining[i] = epochEmissionsRemaining[i];
		}
	}
}
