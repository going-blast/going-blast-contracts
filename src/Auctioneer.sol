// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IWETH } from "./WETH9.sol";
import "./IAuctioneer.sol";
import { GBMath } from "./AuctionUtils.sol";
import { BlastYield } from "./BlastYield.sol";
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
	using EnumerableSet for EnumerableSet.UintSet;

	IERC20 public VOUCHER;
	IWETH public WETH;

	address public treasury;
	uint256 public treasuryCut;
	address public deadAddress = 0x000000000000000000000000000000000000dEaD;

	IAuctioneerAuction public auctioneerAuction;

	mapping(uint256 => mapping(address => AuctionUser)) public auctionUsers;
	mapping(address => EnumerableSet.UintSet) userParticipatedAuctions;
	mapping(address => string) public userAlias;
	mapping(string => address) public aliasUser;

	mapping(address => bool) public mutedUsers;
	bytes32 public constant MOD_ROLE = keccak256("MOD_ROLE");

	bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");
	bool public createAuctionRequiresRole = true;
	EnumerableSet.UintSet activeLots;

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	constructor(IERC20 _voucher, IWETH _weth) {
		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_grantRole(MOD_ROLE, msg.sender);
		_grantRole(CREATOR_ROLE, msg.sender);

		VOUCHER = _voucher;
		WETH = _weth;
	}

	function link(address _auctioneerAuction) external onlyAdmin {
		if (_auctioneerAuction == address(0)) revert ZeroAddress();
		if (address(auctioneerAuction) != address(0)) revert AlreadyLinked();

		auctioneerAuction = IAuctioneerAuction(_auctioneerAuction);

		emit Linked(address(this), _auctioneerAuction);
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	receive() external payable {}

	modifier onlyAdmin() {
		_checkRole(DEFAULT_ADMIN_ROLE);
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

	function muteUser(address _user, bool _muted) external onlyRole(MOD_ROLE) {
		mutedUsers[_user] = _muted;
		aliasUser[userAlias[_user]] = address(0);
		userAlias[_user] = "";

		emit MutedUser(_user, _muted);
	}

	function setCreateAuctionRequiresRole(bool _required) external onlyAdmin {
		createAuctionRequiresRole = _required;

		emit UpdatedCreateAuctionRequiresRole(_required);
	}

	function updateTreasuryCut(uint256 _treasuryCut) external onlyAdmin {
		if (_treasuryCut > 2000) revert Invalid();
		treasuryCut = _treasuryCut;

		emit UpdatedTreasuryCut(_treasuryCut);
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function createAuction(AuctionParams memory _param) external nonReentrant returns (uint256 lot) {
		if (treasury == address(0)) revert TreasuryNotSet();
		if (createAuctionRequiresRole) {
			_checkRole(CREATOR_ROLE);
		}

		uint256 wethAmount = 0;

		for (uint8 i = 0; i < _param.tokens.length; i++) {
			if (_param.tokens[i].token != address(0)) continue;
			wethAmount += _param.tokens[i].amount;
		}

		if (wethAmount > 0) {
			IERC20(address(WETH)).safeTransferFrom(msg.sender, address(this), wethAmount);
			WETH.withdraw(wethAmount);
		}

		lot = auctioneerAuction.createAuction{ value: wethAmount }(msg.sender, _param, treasuryCut);

		activeLots.add(lot);

		emit AuctionCreated(msg.sender, lot);
	}

	function cancelAuction(uint256 _lot) external {
		_cancelAuction(msg.sender, _lot);
		activeLots.remove(_lot);
	}

	function bid(
		uint256 _lot,
		uint8 _rune,
		string calldata _message,
		uint256 _bidCount,
		PaymentType _paymentType
	) external payable nonReentrant {
		_bid(_lot, _rune, _message, _bidCount, _paymentType);
		userParticipatedAuctions[msg.sender].add(_lot);
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

	function messageAuction(uint256 _lot, string memory _message) external nonReentrant {
		if (mutedUsers[msg.sender]) revert Muted();

		auctioneerAuction.validateAuctionRunning(_lot);

		emit Messaged(_lot, msg.sender, _message, userAlias[msg.sender], auctionUsers[_lot][msg.sender].rune);
	}

	function finalizeAuction(uint256 _lot) external nonReentrant {
		_finalizeAuction(_lot);
	}

	function claimLot(uint256 _lot, string calldata _message) external payable nonReentrant {
		AuctionUser storage user = auctionUsers[_lot][msg.sender];

		if (user.lotClaimed) revert UserAlreadyClaimedLot();
		user.lotClaimed = true;

		(
			uint256 userShareOfPayment,
			address creator,
			uint256 _treasuryCut,
			bool triggerFinalization
		) = auctioneerAuction.claimLot(_lot, msg.sender, user.bids, user.rune);

		_takeUserPayment(msg.sender, PaymentType.WALLET, userShareOfPayment, 0);
		_transferRevenue(userShareOfPayment, creator, _treasuryCut);
		userParticipatedAuctions[msg.sender].remove(_lot);

		if (triggerFinalization) _finalizeAuction(_lot);

		emit Claimed(_lot, msg.sender, mutedUsers[msg.sender] ? "" : _message, userAlias[msg.sender], user.rune);
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

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function _cancelAuction(address _canceller, uint256 _lot) internal {
		auctioneerAuction.cancelAuction(_canceller, _lot, hasRole(DEFAULT_ADMIN_ROLE, _canceller));
		emit AuctionCancelled(_canceller, _lot);
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

		(uint256 userBidsAfterPenalty, uint256 auctionBid, uint256 bidCost) = auctioneerAuction.bid(
			_lot,
			IAuctioneerAuction.BidData({
				user: msg.sender,
				prevRune: user.rune,
				newRune: _rune,
				existingBidCount: user.bids,
				arrivingBidCount: _bidCount,
				paymentType: _paymentType
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

	function _finalizeAuction(uint256 _lot) internal {
		(bool triggerCancellation, uint256 revenue, address creator, uint256 _treasuryCut) = auctioneerAuction
			.finalizeAuction(_lot);

		if (triggerCancellation) {
			_cancelAuction(creator, _lot);
		}

		_transferRevenue(revenue, creator, _treasuryCut);

		activeLots.remove(_lot);
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

	function _transferRevenue(uint256 revenue, address creator, uint256 _treasuryCut) internal {
		if (revenue == 0) return;

		uint256 cut = revenue.scaleByBP(_treasuryCut);

		(bool sent, ) = treasury.call{ value: cut }("");
		if (!sent) revert ETHTransferFailed();

		(sent, ) = payable(creator).call{ value: revenue - cut }("");
		if (!sent) revert ETHTransferFailed();
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	function getAliasAndRune(uint256 _lot, address _user) external view returns (uint8 rune, string memory _alias) {
		rune = auctionUsers[_lot][_user].rune;
		_alias = userAlias[_user];
	}

	function getAuctionUser(uint256 _lot, address _user) external view returns (AuctionUser memory) {
		return auctionUsers[_lot][_user];
	}

	function getUserParticipatedAuctions(address _user) public view returns (uint256[] memory lots) {
		uint256 count = userParticipatedAuctions[_user].length();
		lots = new uint256[](count);
		for (uint256 i = 0; i < count; i++) {
			lots[i] = userParticipatedAuctions[_user].at(i);
		}
	}

	function getActiveLots() external view returns (uint256[] memory lots) {
		uint256 count = activeLots.length();
		lots = new uint256[](count);
		for (uint256 i = 0; i < count; i++) {
			lots[i] = activeLots.at(i);
		}
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
