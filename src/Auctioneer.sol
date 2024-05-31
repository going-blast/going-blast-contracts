// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IWETH } from "./WETH9.sol";
import { IAuctioneerFarm } from "./IAuctioneerFarm.sol";
import "./IAuctioneer.sol";
import { BlastYield } from "./BlastYield.sol";
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
// -- ARCH --

contract Auctioneer is AccessControl, ReentrancyGuard, AuctioneerEvents, BlastYield {
	using GBMath for uint256;
	using SafeERC20 for IERC20;

	IERC20 public GO;
	IERC20 public VOUCHER;
	IWETH public WETH;

	address public treasury;
	address public teamTreasury;
	address public deadAddress = 0x000000000000000000000000000000000000dEaD;

	IAuctioneerEmissions public auctioneerEmissions;
	IAuctioneerAuction public auctioneerAuction;
	IAuctioneerFarm public auctioneerFarm;

	mapping(uint256 => mapping(address => AuctionUser)) public auctionUsers;
	mapping(address => string) public userAlias;
	mapping(string => address) public aliasUser;

	mapping(address => bool) public mutedUsers;
	bytes32 public constant MOD_ROLE = keccak256("MOD_ROLE");

	address public multisig;
	bool public deprecated = false;
	uint256 public migrationQueueTimestamp;
	address public migrationDestination;
	uint256 public migrationDelay = 7 days;

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	constructor(address _multisig, IERC20 _go, IERC20 _voucher, IWETH _weth) {
		multisig = _multisig;
		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_grantRole(MOD_ROLE, msg.sender);

		GO = _go;
		VOUCHER = _voucher;
		WETH = _weth;
	}

	function link(address _auctioneerEmissions, address _auctioneerAuction) external onlyAdmin {
		if (_auctioneerEmissions == address(0)) revert ZeroAddress();
		if (_auctioneerAuction == address(0)) revert ZeroAddress();
		if (address(auctioneerEmissions) != address(0)) revert AlreadyLinked();
		if (address(auctioneerAuction) != address(0)) revert AlreadyLinked();

		auctioneerEmissions = IAuctioneerEmissions(_auctioneerEmissions);
		auctioneerAuction = IAuctioneerAuction(_auctioneerAuction);

		emit Linked(address(this), _auctioneerEmissions, _auctioneerAuction);
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	receive() external payable {}

	modifier onlyAdmin() {
		_checkRole(DEFAULT_ADMIN_ROLE);
		_;
	}
	modifier onlyMultisig() {
		if (multisig != msg.sender) revert NotMultisig();
		_;
	}
	modifier notDeprecated() {
		if (deprecated) revert Deprecated();
		_;
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function initializeBlast() external onlyAdmin {
		_initializeBlast();
	}

	function claimYieldAll(address _recipient, uint256 _minClaimRateBips) external onlyAdmin {
		_claimYieldAll(_recipient, _minClaimRateBips);
	}

	function updateTreasury(address _treasury) external onlyAdmin {
		if (_treasury == address(0)) revert ZeroAddress();

		treasury = _treasury;
		auctioneerAuction.updateTreasury(treasury);
		emit UpdatedTreasury(_treasury);
	}

	function updateTeamTreasury(address _teamTreasury) external onlyAdmin {
		if (_teamTreasury == address(0)) revert ZeroAddress();

		teamTreasury = _teamTreasury;
		auctioneerAuction.updateTeamTreasury(teamTreasury);
		emit UpdatedTeamTreasury(_teamTreasury);
	}

	function updateFarm(address _farm) external onlyAdmin {
		auctioneerFarm = IAuctioneerFarm(_farm);
		emit UpdatedFarm(address(auctioneerFarm));
	}

	function muteUser(address _user, bool _muted) external onlyRole(MOD_ROLE) {
		mutedUsers[_user] = _muted;
		aliasUser[userAlias[_user]] = address(0);
		userAlias[_user] = "";

		emit MutedUser(_user, _muted);
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function createAuctions(AuctionParams[] memory _params) external onlyAdmin nonReentrant notDeprecated {
		if (!auctioneerEmissions.emissionsInitialized()) revert EmissionsNotInitialized();
		if (treasury == address(0)) revert TreasuryNotSet();
		if (teamTreasury == address(0)) revert TeamTreasuryNotSet();

		for (uint8 i = 0; i < _params.length; i++) {
			_createAuction(_params[i]);
		}
	}

	function cancelAuction(uint256 _lot) external onlyAdmin {
		_cancelAuction(_lot);
	}

	function bid(
		uint256 _lot,
		uint8 _rune,
		string calldata _message,
		uint256 _bidCount,
		PaymentType _paymentType
	) external payable nonReentrant {
		_bid(_lot, _rune, _message, _bidCount, _paymentType);
	}

	function bidWithPermit(
		uint256 _lot,
		uint8 _rune,
		string calldata _message,
		uint256 _bidCount,
		PaymentType _paymentType,
		PermitData memory _permitData
	) external payable nonReentrant {
		_selfPermit(_permitData);
		_bid(_lot, _rune, _message, _bidCount, _paymentType);
	}

	function selectRune(uint256 _lot, uint8 _rune, string calldata _message) external nonReentrant {
		auctioneerAuction.validatePrivateAuctionEligibility(_lot, _userGoBalance(msg.sender));

		AuctionUser storage user = auctionUsers[_lot][msg.sender];
		user.bids = auctioneerAuction.selectRune(_lot, user.bids, user.rune, _rune);

		uint8 prevRune = user.rune;
		user.rune = _rune;

		emit SelectedRune(
			_lot,
			msg.sender,
			mutedUsers[msg.sender] ? "" : _message,
			userAlias[msg.sender],
			_rune,
			prevRune
		);
	}

	function messageAuction(uint256 _lot, string memory _message) external {
		if (mutedUsers[msg.sender]) revert Muted();

		auctioneerAuction.validateAuctionRunning(_lot);
		auctioneerAuction.validatePrivateAuctionEligibility(_lot, _userGoBalance(msg.sender));

		emit Messaged(_lot, msg.sender, _message, userAlias[msg.sender], auctionUsers[_lot][msg.sender].rune);
	}

	function finalizeAuction(uint256 _lot) external nonReentrant {
		_finalizeAuction(_lot);
	}

	function claimLot(uint256 _lot, string calldata _message) external payable nonReentrant {
		AuctionUser storage user = auctionUsers[_lot][msg.sender];

		if (user.lotClaimed) revert UserAlreadyClaimedLot();
		user.lotClaimed = true;

		(uint256 userShareOfPayment, bool triggerFinalization) = auctioneerAuction.claimLot(
			_lot,
			msg.sender,
			user.bids,
			user.rune
		);

		_takeUserPayment(msg.sender, PaymentType.WALLET, userShareOfPayment, 0);
		_distributeLotPayment(_lot, userShareOfPayment);

		if (triggerFinalization) _finalizeAuction(_lot);

		emit Claimed(_lot, msg.sender, mutedUsers[msg.sender] ? "" : _message, userAlias[msg.sender], user.rune);
	}

	function harvestAuctionsEmissions(uint256[] memory _lots, bool _harvestToFarm) external nonReentrant {
		for (uint256 i = 0; i < _lots.length; i++) {
			_harvestAuctionEmissions(_lots[i], _harvestToFarm);
		}
	}

	function setAlias(string memory _alias) external nonReentrant {
		if (mutedUsers[msg.sender]) revert Muted();
		if (bytes(_alias).length < 3 || bytes(_alias).length > 9) revert InvalidAlias();
		if (aliasUser[_alias] != address(0)) revert AliasTaken();

		// Free previous alias
		aliasUser[userAlias[msg.sender]] = address(0);

		// Set new alias
		userAlias[msg.sender] = _alias;
		aliasUser[_alias] = msg.sender;

		emit UpdatedAlias(msg.sender, _alias);
	}

	// MIGRATION
	//
	// Escape hatch for serious bugs or serious upgrades
	// Migration is behind 10 day timelock and 4 party multisig
	//
	//   I really don't like having this functionality in here, but its
	//   irresponsible to pretend that it could never be necessary. I
	//   see it as the lesser of the evils. I'm not going to steal from
	//   any of you, I've been stolen from in the past, I couldn't imagine
	//   inflicting that on others.
	//
	//      -- Arch
	//

	function queueMigration(address _dest) external onlyMultisig notDeprecated {
		if (_dest == address(0)) revert ZeroAddress();
		if (migrationQueueTimestamp != 0) revert MigrationAlreadyQueued();

		migrationQueueTimestamp = block.timestamp;
		migrationDestination = _dest;

		emit MigrationQueued(multisig, _dest);
	}

	function cancelMigration(address _dest) external onlyMultisig {
		if (migrationQueueTimestamp == 0) revert MigrationNotQueued();
		if (migrationDestination != _dest) revert MigrationDestMismatch();

		migrationQueueTimestamp = 0;
		migrationDestination = address(0);

		emit MigrationQueued(multisig, _dest);
	}

	function executeMigration(address _dest) external onlyMultisig {
		if (migrationQueueTimestamp == 0) revert MigrationNotQueued();
		if (migrationDestination != _dest) revert MigrationDestMismatch();

		deprecated = true;
		uint256 unallocated = auctioneerEmissions.executeMigration(_dest);

		emit MigrationExecuted(multisig, _dest, unallocated);
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function _createAuction(AuctionParams memory _param) internal {
		uint256 wethAmount = 0;

		for (uint8 i = 0; i < _param.tokens.length; i++) {
			if (_param.tokens[i].token != address(0)) continue;
			wethAmount += _param.tokens[i].amount;
		}

		if (wethAmount > 0) {
			IERC20(address(WETH)).safeTransferFrom(treasury, address(this), wethAmount);
			WETH.withdraw(wethAmount);
		}

		uint256 auctionEmissions = auctioneerEmissions.allocateAuctionEmissions(
			_param.unlockTimestamp,
			_param.emissionBP
		);

		uint256 lot = auctioneerAuction.createAuction{ value: wethAmount }(_param, auctionEmissions);

		emit AuctionCreated(lot);
	}

	function _cancelAuction(uint256 _lot) internal {
		(uint256 unlockTimestamp, uint256 cancelledEmissions) = auctioneerAuction.cancelAuction(_lot);
		auctioneerEmissions.deAllocateEmissions(unlockTimestamp, cancelledEmissions);
		emit AuctionCancelled(_lot);
	}

	function _bid(
		uint256 _lot,
		uint8 _rune,
		string calldata _message,
		uint256 _bidCount,
		PaymentType _paymentType
	) internal {
		if (_bidCount == 0) revert InvalidBidCount();

		AuctionUser storage user = auctionUsers[_lot][msg.sender];

		(uint256 userBidsAfterPenalty, uint256 auctionBid, uint256 bidCost) = auctioneerAuction.markBid(
			_lot,
			IAuctioneerAuction.MarkBidPayload({
				user: msg.sender,
				prevRune: user.rune,
				newRune: _rune,
				existingBidCount: user.bids,
				arrivingBidCount: _bidCount,
				paymentType: _paymentType,
				userGoBalance: _userGoBalance(msg.sender)
			})
		);

		uint8 prevRune = user.rune;
		user.rune = _rune;
		user.bids = userBidsAfterPenalty + _bidCount;

		_takeUserPayment(msg.sender, _paymentType, bidCost * _bidCount, _bidCount * 1e18);

		emit Bid(
			_lot,
			msg.sender,
			mutedUsers[msg.sender] ? "" : _message,
			userAlias[msg.sender],
			_rune,
			prevRune,
			auctionBid,
			_bidCount,
			block.timestamp
		);
	}

	function _harvestAuctionEmissions(uint256 _lot, bool _harvestToFarm) internal {
		AuctionUser storage user = auctionUsers[_lot][msg.sender];
		if (user.emissionsHarvested || user.bids == 0) return;

		(uint256 unlockTimestamp, uint256 auctionBids, uint256 biddersEmissions) = auctioneerAuction
			.validateAndGetHarvestData(_lot);

		if (biddersEmissions == 0) return;

		(uint256 harvested, uint256 burned) = auctioneerEmissions.harvestEmissions(
			msg.sender,
			(biddersEmissions * user.bids) / auctionBids,
			unlockTimestamp,
			_harvestToFarm
		);

		user.emissionsHarvested = true;
		user.harvestedEmissions = harvested;
		user.burnedEmissions = burned;

		if (_harvestToFarm && harvested > 0) {
			GO.safeIncreaseAllowance(address(auctioneerFarm), harvested);
			auctioneerFarm.depositLockedGo(
				harvested,
				payable(msg.sender),
				unlockTimestamp + auctioneerEmissions.emissionTaxDuration()
			);
		}

		emit UserHarvestedLotEmissions(_lot, msg.sender, harvested, burned, _harvestToFarm);
	}

	function _finalizeAuction(uint256 _lot) internal {
		(
			bool triggerCancellation,
			uint256 treasuryEmissions,
			uint256 treasuryETHDistribution,
			uint256 farmETHDistribution,
			uint256 teamTreasuryETHDistribution
		) = auctioneerAuction.finalizeAuction(_lot);

		if (triggerCancellation) {
			_cancelAuction(_lot);
		}

		if (treasuryEmissions > 0) {
			auctioneerEmissions.transferEmissions(treasury, treasuryEmissions);
		}

		_transferDistributions(treasuryETHDistribution, farmETHDistribution, teamTreasuryETHDistribution);
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
	function _takeUserPayment(
		address _user,
		PaymentType _paymentType,
		uint256 _ethAmount,
		uint256 _voucherAmount
	) internal {
		if (_paymentType == PaymentType.WALLET) {
			if (msg.value != _ethAmount) revert IncorrectETHPaymentAmount();
		} else {
			if (msg.value != 0) revert SentETHButNotWalletPayment();
		}
		if (_paymentType == PaymentType.VOUCHER) {
			VOUCHER.safeTransferFrom(_user, deadAddress, _voucherAmount);
		}
	}

	function _distributeLotPayment(uint256 _lot, uint256 _userShareOfPayment) internal {
		(uint256 farmDistribution, uint256 teamTreasuryDistribution) = auctioneerAuction.getProfitDistributions(
			_lot,
			_userShareOfPayment
		);

		_transferDistributions(0, farmDistribution, teamTreasuryDistribution);
	}

	function _transferDistributions(
		uint256 treasuryDistribution,
		uint256 farmDistribution,
		uint256 teamTreasuryDistribution
	) internal {
		if (farmDistribution > 0) {
			if (address(auctioneerFarm) != address(0) && auctioneerFarm.distributionReceivable()) {
				// Only send farm distribution if the farm exists and can handle the distribution
				auctioneerFarm.receiveDistribution{ value: farmDistribution }();
			} else {
				// If the farm not available, send the farm distribution to the treasury
				treasuryDistribution += farmDistribution;
			}
		}

		if (treasuryDistribution > 0) {
			(bool sent, ) = treasury.call{ value: treasuryDistribution }("");
			if (!sent) revert ETHTransferFailed();
		}

		if (teamTreasuryDistribution > 0) {
			(bool sent, ) = teamTreasury.call{ value: teamTreasuryDistribution }("");
			if (!sent) revert ETHTransferFailed();
		}
	}

	function _userGoBalance(address _user) internal view returns (uint256 bal) {
		bal = GO.balanceOf(_user);
		if (address(auctioneerFarm) != address(0)) {
			bal += auctioneerFarm.getEqualizedUserStaked(_user);
		}
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function getUserPrivateAuctionData(
		address _user
	) external view returns (uint256 userGO, uint256 requirement, bool permitted) {
		userGO = _userGoBalance(_user);
		requirement = auctioneerAuction.privateAuctionRequirement();
		permitted = userGO >= requirement;
	}

	function getAliasAndRune(uint256 _lot, address _user) external view returns (uint8 rune, string memory _alias) {
		rune = auctionUsers[_lot][_user].rune;
		_alias = userAlias[_user];
	}

	function getAuctionUser(uint256 _lot, address _user) external view returns (AuctionUser memory) {
		return auctionUsers[_lot][_user];
	}

	function getUserLotInfos(uint256[] memory _lots, address _user) external view returns (UserLotInfo[] memory infos) {
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

			if (auctionHasBids && auctionHasRunes && auction.runes[user.rune].bids > 0) {
				infos[i].shareOfLot =
					((user.bids + runicLastBidderBonusBids) * 1e18) /
					auction.runes[user.rune].bids.scaleByBP(10000 + runicLastBidderBonus);
			} else if (auctionHasBids && !auctionHasRunes) {
				infos[i].shareOfLot = 1e18;
			} else {
				infos[i].shareOfLot = 0;
			}

			infos[i].price = (auction.bidData.bid * infos[i].shareOfLot) / 1e18;
		}
	}
}
