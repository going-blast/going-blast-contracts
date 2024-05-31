// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAuctioneerFarm } from "./IAuctioneerFarm.sol";
import "./IAuctioneer.sol";
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

	address public auctioneer;
	bool public emissionsInitialized = false;

	// EMISSIONS
	IERC20 public GO;
	uint256 public startTimestamp;
	uint256 public epochDuration = 90 days;
	uint256 public emissionTaxDuration = 30 days;
	uint256[8] public emissionSharePerEpoch = [128, 64, 32, 16, 8, 4, 2, 1];
	uint256 public emissionSharesTotal = 255;
	uint256 public emissionPerShare = 255e18;
	uint256[8] public epochEmissionsRemaining = [0, 0, 0, 0, 0, 0, 0, 0];

	// HARVEST
	uint256 public earlyHarvestTax = 5000;
	address public deadAddress = 0x000000000000000000000000000000000000dEaD;

	constructor(address _auctioneer, IERC20 _go) Ownable(msg.sender) {
		auctioneer = _auctioneer;
		GO = _go;
	}

	///////////////////
	// MODIFIERS
	///////////////////

	modifier onlyAuctioneer() {
		if (msg.sender != auctioneer) revert NotAuctioneer();
		_;
	}

	///////////////////
	// ADMIN
	///////////////////

	function updateEarlyHarvestTax(uint256 _earlyHarvestTax) public onlyOwner {
		if (_earlyHarvestTax > 8000) revert Invalid();

		earlyHarvestTax = _earlyHarvestTax;
		emit UpdatedEarlyHarvestTax(_earlyHarvestTax);
	}

	function updateEmissionTaxDuration(uint256 _emissionTaxDuration) public onlyOwner {
		if (_emissionTaxDuration > 60 days) revert Invalid();

		emissionTaxDuration = _emissionTaxDuration;
		emit UpdatedEmissionTaxDuration(_emissionTaxDuration);
	}

	// Escape hatch for serious bugs or upgrades
	// Only callable by Auctioneer
	// Auctioneer migration function is behind 7 day timelock and 4 party multisig
	function executeMigration(address _dest) public onlyAuctioneer returns (uint256 unallocated) {
		unallocated = 0;

		// Can't pull GO from already running auctions.
		// Cancel upcoming auctions to free some GO allocations before migrating.
		for (uint8 i = 0; i < 8; i++) {
			unallocated += epochEmissionsRemaining[i];
		}

		GO.safeTransfer(_dest, unallocated);
	}

	///////////////////
	// INITIALIZE
	///////////////////

	function initializeEmissions(uint256 _unlockTimestamp) public onlyOwner {
		if (GO.balanceOf(address(this)) == 0) revert GONotYetReceived();
		if (emissionsInitialized) revert AlreadyInitialized();

		// Set start timestamp
		startTimestamp = _unlockTimestamp;

		// Spread emissions between epochs
		uint256 totalToEmit = GO.balanceOf(address(this));
		for (uint8 i = 0; i < 8; i++) {
			epochEmissionsRemaining[i] = (totalToEmit * emissionSharePerEpoch[i]) / emissionSharesTotal;
		}

		emissionsInitialized = true;
		emit InitializedEmissions();
	}

	///////////////////
	// EPOCH
	///////////////////

	function _getEpochAtTimestamp(uint256 timestamp) internal view returns (uint256 epoch) {
		if (startTimestamp == 0 || timestamp < startTimestamp) return 0;
		epoch = (timestamp - startTimestamp) / epochDuration;
	}

	function _getEpochDataAtTimestamp(uint256 timestamp) internal view returns (EpochData memory epochData) {
		epochData.epoch = _getEpochAtTimestamp(timestamp);

		epochData.start = startTimestamp + (epochData.epoch * epochDuration);
		epochData.end = epochData.start + epochDuration;

		if (timestamp > epochData.end) {
			epochData.daysRemaining = 0;
		} else {
			epochData.daysRemaining = ((epochData.end - timestamp) / 1 days);
		}

		// Emissions only exist for first 8 epochs, prevent array out of bounds
		epochData.emissionsRemaining = epochData.epoch >= 8 ? 0 : epochEmissionsRemaining[epochData.epoch];

		epochData.dailyEmission = (epochData.emissionsRemaining == 0 || epochData.daysRemaining == 0)
			? 0
			: epochData.emissionsRemaining / epochData.daysRemaining;
	}

	///////////////////
	// ALLOCATION
	///////////////////

	function _getAuctionEmission(uint256 _unlockTimestamp, uint256 _bp) internal view returns (uint256 emissions) {
		EpochData memory epochData = _getEpochDataAtTimestamp(_unlockTimestamp);
		emissions = epochData.dailyEmission;

		if (emissions == 0) return 0;

		// Modulate with auction _bp (percent of daily emission)
		emissions = emissions.scaleByBP(_bp);

		// Check to prevent stealing emissions from next epoch
		//  (would only happen if it's the last day of the epoch and _bp > 10000)
		if (emissions > epochData.emissionsRemaining) {
			emissions = epochData.emissionsRemaining;
		}
	}

	function getAuctionEmission(uint256 _unlockTimestamp, uint256 _bp) public view returns (uint256 emissions) {
		return _getAuctionEmission(_unlockTimestamp, _bp);
	}

	function allocateAuctionEmissions(
		uint256 _unlockTimestamp,
		uint256 _bp
	) public onlyAuctioneer returns (uint256 emissions) {
		uint256 epoch = _getEpochAtTimestamp(_unlockTimestamp);
		emissions = _getAuctionEmission(_unlockTimestamp, _bp);

		// Mark emissions as allocated
		if (emissions > 0) {
			epochEmissionsRemaining[epoch] -= emissions;
		}
	}

	function deAllocateEmissions(uint256 _unlockTimestamp, uint256 _emissionsToDeAllocate) public onlyAuctioneer {
		uint256 epoch = _getEpochAtTimestamp(_unlockTimestamp);
		if (epoch < 8) {
			epochEmissionsRemaining[epoch] += _emissionsToDeAllocate;
		}
	}

	///////////////////
	// TRANSFER
	///////////////////

	function _transferEmissions(address _to, uint256 _amount) internal {
		if (_amount == 0) return;
		GO.safeTransfer(_to, _amount);
	}

	function transferEmissions(address _to, uint256 _amount) public onlyAuctioneer {
		_transferEmissions(_to, _amount);
	}

	function harvestEmissions(
		address _user,
		uint256 _emissions,
		uint256 _emissionsEarnedTimestamp,
		bool _harvestToFarm
	) public onlyAuctioneer returns (uint256 harvested, uint256 burned) {
		// If emissions should be taxed
		bool incursTax = !_harvestToFarm && block.timestamp < (_emissionsEarnedTimestamp + emissionTaxDuration);

		// Calculate emission amounts
		harvested = _emissions.scaleByBP(incursTax ? (10000 - earlyHarvestTax) : 10000);
		burned = _emissions - harvested;

		// Harvest emissions
		_transferEmissions(_harvestToFarm ? auctioneer : _user, harvested);

		// Burn emissions
		_transferEmissions(deadAddress, burned);
	}

	///////////////////
	// VIEW
	///////////////////

	function getEpochDataAtTimestamp(uint256 _timestamp) public view returns (EpochData memory epochData) {
		return _getEpochDataAtTimestamp(_timestamp);
	}
	function getCurrentEpochData() public view returns (uint256) {
		return _getEpochAtTimestamp(block.timestamp);
	}
	function getEmissionSharePerEpoch() public view returns (uint256[] memory share) {
		share = new uint256[](8);
		for (uint8 i = 0; i < 8; i++) {
			share[i] = emissionSharePerEpoch[i];
		}
	}
	function getEpochEmissionsRemaining() public view returns (uint256[] memory share) {
		share = new uint256[](8);
		for (uint8 i = 0; i < 8; i++) {
			share[i] = epochEmissionsRemaining[i];
		}
	}
}
