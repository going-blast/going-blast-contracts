// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AuctionViewUtils, GBMath } from "../src/AuctionUtils.sol";

contract AuctioneerMigrateTest is AuctioneerHelper {
	using GBMath for uint256;
	using SafeERC20 for IERC20;
	using AuctionViewUtils for Auction;

	function setUp() public override {
		super.setUp();

		_distributeGO();
		_initializeAuctioneerEmissions();
		_setupAuctioneerTreasury();
		_setupAuctioneerTeamTreasury();
		_giveUsersTokensAndApprove();
		_auctioneerUpdateFarm();
		_initializeFarmEmissions();
		_giveTreasuryXXandYYandApprove();

		AuctionParams[] memory params = new AuctionParams[](2);
		// Create single token auction
		params[0] = _getBaseSingleAuctionParams();
		// Create multi token auction
		params[1] = _getBaseSingleAuctionParams();
		params[1].isPrivate = true;

		auctioneer.createAuctions(params);
	}

	function test_migration_ExpectRevert_NotMultisig() public {
		vm.expectRevert(NotMultisig.selector);
		auctioneer.queueMigration(treasury);

		vm.expectRevert(NotMultisig.selector);
		auctioneer.cancelMigration(treasury);

		vm.expectRevert(NotMultisig.selector);
		auctioneer.executeMigration(treasury);
	}

	function test_migrationQueue_ExpectEmit_MigrationQueued() public {
		vm.expectEmit(true, true, true, true);
		emit MigrationQueued(multisig, treasury);

		vm.prank(multisig);
		auctioneer.queueMigration(treasury);

		assertEq(auctioneer.migrationQueueTimestamp(), block.timestamp, "Migration queue timestamp set");
		assertEq(auctioneer.migrationDestination(), treasury, "Migration destination set");
	}

	function test_migrationQueue_ExpectRevert_MigrationAlreadyQueued() public {
		vm.prank(multisig);
		auctioneer.queueMigration(treasury);

		assertEq(auctioneer.migrationQueueTimestamp(), block.timestamp, "Migration queue timestamp set");

		vm.expectRevert(MigrationAlreadyQueued.selector);

		vm.prank(multisig);
		auctioneer.queueMigration(treasury);
	}

	function test_migrationQueue_ExpectRevert_ZeroAddress() public {
		vm.expectRevert(ZeroAddress.selector);

		vm.prank(multisig);
		auctioneer.queueMigration(address(0));
	}

	function test_migrationCancel_ExpectRevert_MigrationNotQueued() public {
		vm.expectRevert(MigrationNotQueued.selector);

		vm.prank(multisig);
		auctioneer.cancelMigration(treasury);
	}

	function test_migrationCancel_ExpectRevert_MigrationDestMismatch() public {
		vm.prank(multisig);
		auctioneer.queueMigration(treasury);

		vm.expectRevert(MigrationDestMismatch.selector);

		vm.prank(multisig);
		auctioneer.cancelMigration(multisig);
	}

	function test_migrationCancel_ExpectEmit_MigrationCancelled() public {
		vm.prank(multisig);
		auctioneer.queueMigration(treasury);

		assertEq(auctioneer.migrationQueueTimestamp(), block.timestamp, "Migration queue timestamp set");
		assertEq(auctioneer.migrationDestination(), treasury, "Migration destination set");

		vm.expectEmit(true, true, true, true);
		emit MigrationCancelled(multisig, treasury);

		vm.prank(multisig);
		auctioneer.cancelMigration(treasury);

		assertEq(auctioneer.migrationQueueTimestamp(), 0, "Migration queue timestamp reverted");
		assertEq(auctioneer.migrationDestination(), address(0), "Migration destination reverted");
	}

	function test_migrationExecute_ExpectRevert_MigrationNotQueued() public {
		vm.expectRevert(MigrationNotQueued.selector);

		vm.prank(multisig);
		auctioneer.executeMigration(treasury);
	}

	function test_migrationExecute_ExpectRevert_MigrationDestMismatch() public {
		vm.prank(multisig);
		auctioneer.queueMigration(treasury);

		vm.expectRevert(MigrationDestMismatch.selector);

		vm.prank(multisig);
		auctioneer.executeMigration(multisig);
	}

	function test_migrationExecute_ExpectRevert_MigrationNotMature() public {
		vm.prank(multisig);
		auctioneer.queueMigration(treasury);

		vm.expectRevert(MigrationNotMature.selector);

		vm.prank(multisig);
		auctioneer.executeMigration(treasury);

		vm.warp(auctioneer.migrationQueueTimestamp() + 7 days - 1);
		vm.expectRevert(MigrationNotMature.selector);

		vm.prank(multisig);
		auctioneer.executeMigration(treasury);
	}

	function _getEmissionsRemaining() internal view returns (uint256 emissionsRemaining) {
		uint256[] memory epochEmissionsRemaining = auctioneerEmissions.getEpochEmissionsRemaining();
		for (uint8 i = 0; i < 8; i++) {
			emissionsRemaining += epochEmissionsRemaining[i];
		}
	}

	function test_migrationExecute_ExpectEmit_MigrationExecuted() public {
		vm.prank(multisig);
		auctioneer.queueMigration(treasury);

		uint256 emissionsRemaining = _getEmissionsRemaining();

		_expectTokenTransfer(GO, address(auctioneerEmissions), treasury, emissionsRemaining);

		vm.warp(auctioneer.migrationQueueTimestamp() + 7 days);
		vm.expectEmit(true, true, true, true);
		emit MigrationExecuted(multisig, treasury, emissionsRemaining);

		vm.prank(multisig);
		auctioneer.executeMigration(treasury);
	}

	function test_migrationExecute_CancellingAuctionsReturnsAllFunds() public {
		vm.prank(multisig);
		auctioneer.queueMigration(treasury);

		uint256 emissionsRemainingInit = _getEmissionsRemaining();
		auctioneer.cancelAuction(0);
		auctioneer.cancelAuction(1);
		uint256 emissionsRemainingFinal = _getEmissionsRemaining();
		assertGt(emissionsRemainingFinal, emissionsRemainingInit, "Allocated emissions returned to epoch");

		console.log("Initial Emissions Remaining", emissionsRemainingInit);
		console.log("Final Emissions Remaining", emissionsRemainingFinal);

		_expectTokenTransfer(GO, address(auctioneerEmissions), treasury, emissionsRemainingFinal);

		vm.warp(auctioneer.migrationQueueTimestamp() + 7 days);
		vm.expectEmit(true, true, true, true);
		emit MigrationExecuted(multisig, treasury, emissionsRemainingFinal);

		vm.prank(multisig);
		auctioneer.executeMigration(treasury);
	}

	function _executeFullMigration() internal {
		vm.prank(multisig);
		auctioneer.queueMigration(treasury);

		vm.warp(auctioneer.migrationQueueTimestamp() + 7 days);

		vm.prank(multisig);
		auctioneer.executeMigration(treasury);
	}

	function test_migrationExecute_Expect_DeprecatedSetToTrue() public {
		_executeFullMigration();

		assertEq(auctioneer.deprecated(), true, "Deprecated set to true after migration");
	}

	function test_migration_AlreadyMigrated_ExpectRevert_Deprecated() public {
		_executeFullMigration();

		vm.expectRevert(Deprecated.selector);
		vm.prank(multisig);
		auctioneer.queueMigration(treasury);

		vm.expectRevert(Deprecated.selector);
		vm.prank(multisig);
		auctioneer.cancelMigration(treasury);

		vm.expectRevert(Deprecated.selector);
		vm.prank(multisig);
		auctioneer.executeMigration(treasury);
	}

	function test_migration_createAuctions_AlreadyMigrated_ExpectRevert_Deprecated() public {
		_executeFullMigration();

		vm.expectRevert(Deprecated.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createAuctions(params);
	}
}
