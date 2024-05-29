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
import { IAuctioneerUser } from "./AuctioneerUser.sol";
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
	IAuctioneerUser public auctioneerUser;
	IAuctioneerEmissions public auctioneerEmissions;
	IAuctioneerAuction public auctioneerAuction;
	IAuctioneerFarm public auctioneerFarm;

	// ADMIN
	address public treasury;
	address public deadAddress = 0x000000000000000000000000000000000000dEaD;

	IERC20 public GO;
	IERC20 public VOUCHER;
	IWETH public WETH;

	constructor(IERC20 _go, IERC20 _voucher, IWETH _weth) Ownable(msg.sender) {
		GO = _go;
		VOUCHER = _voucher;
		WETH = _weth;
	}

	function link(address _auctioneerUser, address _auctioneerEmissions, address _auctioneerAuction) public onlyOwner {
		if (_auctioneerUser == address(0) || _auctioneerEmissions == address(0) || _auctioneerAuction == address(0))
			revert ZeroAddress();
		if (address(auctioneerUser) != address(0)) revert AlreadyLinked();
		if (address(auctioneerEmissions) != address(0)) revert AlreadyLinked();
		if (address(auctioneerAuction) != address(0)) revert AlreadyLinked();

		auctioneerEmissions = IAuctioneerEmissions(_auctioneerEmissions);
		auctioneerEmissions.link(_auctioneerUser);

		auctioneerUser = IAuctioneerUser(_auctioneerUser);
		auctioneerUser.link(_auctioneerEmissions, _auctioneerAuction);

		auctioneerAuction = IAuctioneerAuction(_auctioneerAuction);
		auctioneerAuction.link();

		emit Linked(address(this), _auctioneerUser, _auctioneerEmissions, _auctioneerAuction);
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
		(uint8 rune, string memory _alias) = auctioneerUser.getAliasAndRune(_lot, msg.sender);
		emit AuctionEvent(_lot, msg.sender, AuctionEventType.MESSAGE, _message, _alias, rune);
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
		(uint256 prevUserBids, uint8 prevRune, string memory _alias) = auctioneerUser.bid(_lot, msg.sender, _options);

		// Auction bid
		(uint256 userBid, uint256 bidCost) = auctioneerAuction.markBid(
			_lot,
			msg.sender,
			prevUserBids,
			prevRune,
			_userGOBalance(msg.sender),
			_options
		);

		// Payment
		_takeUserPayment(msg.sender, _options.paymentType, bidCost * _options.multibid, _options.multibid * 1e18);

		emit AuctionEvent(
			_lot,
			msg.sender,
			AuctionEventType.RUNE,
			_options.message,
			_alias,
			_options.multibid,
			prevRune,
			_options.rune,
			block.timestamp
		);
	}

	function selectRune(uint256 _lot, uint8 _rune, string calldata _message) public nonReentrant {
		(uint256 userBids, uint8 prevRune, string memory _alias) = auctioneerUser.selectRune(_lot, msg.sender, _rune);
		auctioneerAuction.selectRune(_lot, userBids, prevRune, _rune);

		emit AuctionEvent(_lot, msg.sender, AuctionEventType.RUNE, _message, _alias, 0, prevRune, _rune, block.timestamp);
	}

	// CLAIM

	function claimLot(uint256 _lot, string calldata _message) public payable nonReentrant {
		// Mark user claimed
		(uint8 userRune, uint256 userBids, string memory _alias) = auctioneerUser.claimLot(_lot, msg.sender);

		(uint256 userShareOfLot, uint256 userShareOfPayment, bool triggerFinalization) = auctioneerAuction.claimLot(
			_lot,
			msg.sender,
			userBids,
			userRune
		);

		// Take Payment
		_takeUserPayment(msg.sender, PaymentType.WALLET, userShareOfPayment, 0);

		// Distribute Payment
		_distributeLotProfit(_lot, userShareOfPayment);

		// Finalize
		if (triggerFinalization) {
			finalize(_lot);
		}

		emit AuctionEvent(_lot, msg.sender, AuctionEventType.CLAIM, _message, _alias, userRune);
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
		(uint256 unlockTimestamp, uint256 bids, uint256 biddersEmissions) = auctioneerAuction.validateAndGetHarvestData(
			_lot
		);

		(uint256 harvested, uint256 burned) = auctioneerUser.harvestAuctionEmissions(
			_lot,
			msg.sender,
			unlockTimestamp,
			bids,
			biddersEmissions,
			_harvestToFarm
		);

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
}
