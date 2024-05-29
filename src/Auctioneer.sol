// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
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

contract Auctioneer is Ownable, ReentrancyGuard, AuctioneerEvents, BlastYield {
	using GBMath for uint256;
	using SafeERC20 for IERC20;

	// FACETS (not really)
	IAuctioneerEmissions public auctioneerEmissions;
	IAuctioneerAuction public auctioneerAuction;
	IAuctioneerFarm public auctioneerFarm;

	// ADMIN
	address public treasury;
	address public deadAddress = 0x000000000000000000000000000000000000dEaD;

	IERC20 public GO;
	IERC20 public VOUCHER;
	IWETH public WETH;

	// USER
	mapping(uint256 => mapping(address => AuctionUser)) public auctionUsers;
	mapping(address => string) public userAlias;
	mapping(string => address) public aliasUser;

	constructor(IERC20 _go, IERC20 _voucher, IWETH _weth) Ownable(msg.sender) {
		GO = _go;
		VOUCHER = _voucher;
		WETH = _weth;
	}

	function link(address _auctioneerEmissions, address _auctioneerAuction) public onlyOwner {
		if (_auctioneerEmissions == address(0) || _auctioneerAuction == address(0)) revert ZeroAddress();
		if (address(auctioneerEmissions) != address(0)) revert AlreadyLinked();
		if (address(auctioneerAuction) != address(0)) revert AlreadyLinked();

		auctioneerEmissions = IAuctioneerEmissions(_auctioneerEmissions);
		auctioneerEmissions.link();

		auctioneerAuction = IAuctioneerAuction(_auctioneerAuction);
		auctioneerAuction.link();

		emit Linked(address(this), _auctioneerEmissions, _auctioneerAuction);
	}

	// RECEIVERS

	receive() external payable {}

	// Admin

	function updateTreasury(address _treasury) public onlyOwner {
		if (_treasury == address(0)) revert ZeroAddress();
		treasury = _treasury;
		auctioneerAuction.updateTreasury(treasury);
		emit UpdatedTreasury(_treasury);
	}

	function updateFarm(address _farm) public onlyOwner {
		auctioneerFarm = IAuctioneerFarm(_farm);
		auctioneerFarm.link();
		emit UpdatedFarm(address(auctioneerFarm));
	}

	// BLAST

	function initializeBlast() public onlyOwner {
		_initializeBlast();
	}

	function claimYieldAll(address _recipient, uint256 _minClaimRateBips) public onlyOwner {
		_claimYieldAll(_recipient, _minClaimRateBips);
	}

	// PRIVATE AUCTION

	function _userGOBalance(address _user) internal view returns (uint256 bal) {
		bal = GO.balanceOf(_user);
		if (address(auctioneerFarm) != address(0)) {
			bal += auctioneerFarm.getEqualizedUserStaked(_user);
		}
	}

	///////////////////
	// CORE
	///////////////////

	function createAuctions(AuctionParams[] memory _params) public onlyOwner nonReentrant {
		if (!auctioneerEmissions.emissionsInitialized()) revert EmissionsNotInitialized();
		if (treasury == address(0)) revert TreasuryNotSet();

		uint256 ethAmount = 0;

		// Pull WETH from treasury, must use WETH so that the owner doesn't also need to be the treasury
		for (uint8 i = 0; i < _params.length; i++) {
			for (uint8 j = 0; j < _params[i].tokens.length; j++) {
				if (_params[i].tokens[j].token == address(0)) {
					ethAmount += _params[i].tokens[j].amount;
				}
			}
		}

		if (ethAmount > 0) {
			IERC20(address(WETH)).safeTransferFrom(treasury, address(this), ethAmount);
			WETH.withdraw(ethAmount);
		}

		for (uint8 i = 0; i < _params.length; i++) {
			// Allocate Emissions
			uint256 auctionEmissions = auctioneerEmissions.allocateAuctionEmissions(
				_params[i].unlockTimestamp,
				_params[i].emissionBP
			);

			// Reset lotETH to prevent blending
			uint256 lotEth = 0;

			// Get amount of ETH that needs to be sent
			for (uint8 j = 0; j < _params[i].tokens.length; j++) {
				if (_params[i].tokens[j].token == address(0)) {
					lotEth = _params[i].tokens[j].amount;
				}
			}

			// Create Auction
			uint256 lot = auctioneerAuction.createAuction{ value: lotEth }(_params[i], auctionEmissions);

			emit AuctionCreated(lot);
			emit AuctionEvent(lot, address(0), AuctionEventType.INFO, "CREATED");
		}
	}

	// CANCEL

	function cancelAuction(uint256 _lot) public onlyOwner {
		(uint256 unlockTimestamp, uint256 cancelledEmissions) = auctioneerAuction.cancelAuction(_lot);

		auctioneerEmissions.deAllocateEmissions(unlockTimestamp, cancelledEmissions);
		emit AuctionCancelled(_lot);
		emit AuctionEvent(_lot, address(0), AuctionEventType.INFO, "CANCELLED");
	}

	// USER PAYMENT

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

	// MESSAGE
	function messageAuction(uint256 _lot, string memory _message) public {
		emit AuctionEvent(
			_lot,
			msg.sender,
			AuctionEventType.MESSAGE,
			_message,
			userAlias[msg.sender],
			auctionUsers[_lot][msg.sender].rune
		);
	}

	// BID

	function bidWithPermit(
		uint256 _lot,
		BidOptions memory _options,
		PermitData memory _permitData
	) public payable nonReentrant {
		_selfPermit(_permitData);
		_bid(_lot, _options);
	}

	function bid(uint256 _lot, BidOptions memory _options) public payable nonReentrant {
		_bid(_lot, _options);
	}

	function _bid(uint256 _lot, BidOptions memory _options) internal {
		// Force bid count to be at least one
		if (_options.multibid == 0) _options.multibid = 1;

		// User bid
		AuctionUser storage user = auctionUsers[_lot][msg.sender];
		uint8 prevRune = user.rune;

		// Auction bid
		(uint256 userBid, uint256 bidCost) = auctioneerAuction.markBid(
			_lot,
			msg.sender,
			user.bids,
			prevRune,
			_userGOBalance(msg.sender),
			_options
		);

		// Update User
		{
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
		}

		// Payment
		_takeUserPayment(msg.sender, _options.paymentType, bidCost * _options.multibid, _options.multibid * 1e18);

		emit AuctionEvent(
			_lot,
			msg.sender,
			AuctionEventType.BID,
			_options.message,
			userAlias[msg.sender],
			_options.multibid,
			prevRune,
			_options.rune,
			block.timestamp
		);
	}

	function selectRune(uint256 _lot, uint8 _rune, string calldata _message) public nonReentrant {
		AuctionUser storage user = auctionUsers[_lot][msg.sender];

		auctioneerAuction.selectRune(_lot, user.bids, user.rune, _rune);

		emit AuctionEvent(
			_lot,
			msg.sender,
			AuctionEventType.RUNE,
			_message,
			userAlias[msg.sender],
			0,
			user.rune,
			_rune,
			block.timestamp
		);

		// Incur rune switch penalty
		if (user.rune != _rune) {
			user.bids = user.bids.scaleByBP(10000 - auctioneerAuction.runeSwitchPenalty());
			user.rune = _rune;
		}
	}

	// CLAIM

	function claimLot(uint256 _lot, string calldata _message) public payable nonReentrant {
		AuctionUser storage user = auctionUsers[_lot][msg.sender];

		// Winner has already paid for and claimed the lot (or their share of it)
		if (user.lotClaimed) revert UserAlreadyClaimedLot();

		// Mark lot as claimed
		user.lotClaimed = true;

		(uint256 userShareOfLot, uint256 userShareOfPayment, bool triggerFinalization) = auctioneerAuction.claimLot(
			_lot,
			msg.sender,
			user.bids,
			user.rune
		);

		// Take Payment
		_takeUserPayment(msg.sender, PaymentType.WALLET, userShareOfPayment, 0);

		// Distribute Payment
		_distributeLotProfit(_lot, userShareOfPayment);

		// Finalize
		if (triggerFinalization) {
			finalize(_lot);
		}

		emit AuctionEvent(_lot, msg.sender, AuctionEventType.CLAIM, _message, userAlias[msg.sender], user.rune);
	}

	function _distributeLotProfit(uint256 _lot, uint256 _userShareOfPayment) internal {
		(uint256 treasuryDistribution, uint256 farmDistribution) = auctioneerAuction.getProfitDistributions(
			_lot,
			_userShareOfPayment
		);

		_sendDistributions(treasuryDistribution, farmDistribution);
	}

	function _sendDistributions(uint256 treasuryDistribution, uint256 farmDistribution) internal {
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
	}

	// FINALIZE

	function finalizeAuction(uint256 _lot) public nonReentrant {
		finalize(_lot);
	}
	function finalize(uint256 _lot) internal {
		(
			bool triggerCancellation,
			uint256 treasuryEmissions,
			uint256 treasuryETHDistribution,
			uint256 farmETHDistribution
		) = auctioneerAuction.finalizeAuction(_lot);

		if (triggerCancellation) {
			cancelAuction(_lot);
		}

		if (treasuryEmissions > 0) {
			auctioneerEmissions.transferEmissions(treasury, treasuryEmissions);
		}

		_sendDistributions(treasuryETHDistribution, farmETHDistribution);
	}

	// HARVEST

	function harvestAuctionsEmissions(uint256[] memory _lots, bool _harvestToFarm) public nonReentrant {
		for (uint256 i = 0; i < _lots.length; i++) {
			harvestAuctionEmissions(_lots[i], _harvestToFarm);
		}
	}

	function harvestAuctionEmissions(uint256 _lot, bool _harvestToFarm) internal {
		AuctionUser storage user = auctionUsers[_lot][msg.sender];

		// Exit if user already harvested emissions from auction
		// Exit early if nothing to claim
		if (user.emissionsHarvested || user.bids == 0) return;

		(uint256 unlockTimestamp, uint256 auctionBids, uint256 biddersEmissions) = auctioneerAuction
			.validateAndGetHarvestData(_lot);

		if (biddersEmissions == 0) return;

		// Mark harvested
		user.emissionsHarvested = true;

		// Signal auctioneerEmissions to harvest user's emissions
		(uint256 harvested, uint256 burned) = auctioneerEmissions.harvestEmissions(
			msg.sender,
			(biddersEmissions * user.bids) / auctionBids,
			unlockTimestamp,
			_harvestToFarm
		);

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

	// VIEW

	function getUserPrivateAuctionData(
		address _user
	) public view returns (uint256 userGO, uint256 requirement, bool permitted) {
		userGO = _userGOBalance(_user);
		requirement = auctioneerAuction.privateAuctionRequirement();
		permitted = userGO >= requirement;
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

	// USER VIEW

	function getAliasAndRune(uint256 _lot, address _user) public view returns (uint8 rune, string memory _alias) {
		rune = auctionUsers[_lot][_user].rune;
		_alias = userAlias[_user];
	}

	function getAuctionUser(uint256 _lot, address _user) public view returns (AuctionUser memory) {
		return auctionUsers[_lot][_user];
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
