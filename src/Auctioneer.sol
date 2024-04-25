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

	IERC20 public USD;
	IERC20 public GO;
	IERC20 public VOUCHER;
	IWETH public WETH;

	constructor(IERC20 _go, IERC20 _voucher, IERC20 _usd, IWETH _weth) Ownable(msg.sender) {
		GO = _go;
		VOUCHER = _voucher;
		USD = _usd;
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
		USD.safeIncreaseAllowance(address(auctioneerUser), type(uint256).max);

		auctioneerAuction = IAuctioneerAuction(_auctioneerAuction);
		auctioneerAuction.link();
		USD.safeIncreaseAllowance(address(auctioneerAuction), type(uint256).max);

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
		if (address(auctioneerAuction) == address(0)) revert ZeroAddress();
		auctioneerFarm = IAuctioneerFarm(_farm);
		auctioneerAuction.updateFarm(_farm);
		auctioneerFarm.link(address(auctioneerAuction));
		emit UpdatedFarm(address(auctioneerFarm));
	}

	// BLAST

	function initializeBlast() public onlyOwner {
		_initializeBlast(address(USD), address(WETH));
	}

	function claimYieldAll(
		address _recipient,
		uint256 _amountWETH,
		uint256 _amountUSDB,
		uint256 _minClaimRateBips
	) public onlyOwner {
		_claimYieldAll(_recipient, _amountWETH, _amountUSDB, _minClaimRateBips);
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

		for (uint8 i = 0; i < _params.length; i++) {
			// Allocate Emissions
			uint256 auctionEmissions = auctioneerEmissions.allocateAuctionEmissions(
				_params[i].unlockTimestamp,
				_params[i].emissionBP
			);

			// Create Auction
			uint256 lot = auctioneerAuction.createAuction(_params[i], auctionEmissions);

			emit AuctionCreated(lot);
		}
	}

	// CANCEL

	function cancelAuction(uint256 _lot, bool _unwrapETH) public onlyOwner {
		(uint256 unlockTimestamp, uint256 cancelledEmissions) = auctioneerAuction.cancelAuction(_lot, _unwrapETH);

		auctioneerEmissions.deAllocateEmissions(unlockTimestamp, cancelledEmissions);
		emit AuctionCancelled(_lot);
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
		uint256 _usdAmount,
		uint256 _voucherAmount
	) internal {
		if (_paymentType == PaymentType.WALLET) {
			USD.safeTransferFrom(_user, address(this), _usdAmount);
		}
		if (_paymentType == PaymentType.FUNDS) {
			auctioneerUser.payFromFunds(_user, _usdAmount);
		}
		if (_paymentType == PaymentType.VOUCHER) {
			VOUCHER.safeTransferFrom(_user, deadAddress, _voucherAmount);
		}
	}

	// BID

	function bidWithPermit(uint256 _lot, BidOptions memory _options, PermitData memory _permitData) public nonReentrant {
		_selfPermit(_permitData);
		_bid(_lot, _options);
	}

	function bid(uint256 _lot, BidOptions memory _options) public nonReentrant {
		_bid(_lot, _options);
	}

	function _bid(uint256 _lot, BidOptions memory _options) internal {
		// Force bid count to be at least one
		if (_options.multibid == 0) _options.multibid = 1;

		// User bid
		(uint256 prevUserBids, uint8 prevRune, string memory userAlias) = auctioneerUser.bid(_lot, msg.sender, _options);

		// Auction bid
		(uint256 userBid, uint256 bidCost, bool auctionHasEmissions) = auctioneerAuction.markBid(
			_lot,
			msg.sender,
			prevUserBids,
			prevRune,
			_userGOBalance(msg.sender),
			_options
		);

		// Mark user will be able to harvest emissions from this auction after it ends
		if (auctionHasEmissions) {
			auctioneerUser.markAuctionHarvestable(_lot, msg.sender);
		}

		// Payment
		_takeUserPayment(msg.sender, _options.paymentType, bidCost * _options.multibid, _options.multibid * 1e18);

		emit Bid(_lot, msg.sender, userBid, userAlias, _options, block.timestamp);
	}

	function selectRune(uint256 _lot, uint8 _rune) public nonReentrant {
		(uint256 userBids, uint8 prevRune) = auctioneerUser.selectRune(_lot, msg.sender, _rune);
		auctioneerAuction.selectRune(_lot, userBids, prevRune, _rune);

		emit PreselectedRune(_lot, msg.sender, _rune);
	}

	// CLAIM

	function claimLotWithPermit(
		uint256 _lot,
		ClaimLotOptions memory _options,
		PermitData memory _permitData
	) public nonReentrant {
		_selfPermit(_permitData);
		_claimLot(_lot, _options);
	}

	function claimLot(uint256 _lot, ClaimLotOptions memory _options) public nonReentrant {
		_claimLot(_lot, _options);
	}

	function _claimLot(uint256 _lot, ClaimLotOptions memory _options) internal {
		if (_options.paymentType == PaymentType.VOUCHER) revert CannotPayForLotWithVouchers();

		// Mark user claimed
		(uint8 userRune, uint256 userBids) = auctioneerUser.claimLot(_lot, msg.sender);

		(, uint256 userShareOfPayment, bool triggerFinalization) = auctioneerAuction.claimLot(
			_lot,
			msg.sender,
			userBids,
			userRune,
			_options
		);

		// Take Payment
		_takeUserPayment(msg.sender, _options.paymentType, userShareOfPayment, 0);

		// Distribute Payment
		auctioneerAuction.distributeLotProfit(_lot, userShareOfPayment);

		// Finalize
		if (triggerFinalization) {
			finalize(_lot);
		}
	}

	// FINALIZE

	function finalizeAuction(uint256 _lot) public nonReentrant {
		finalize(_lot);
	}
	function finalize(uint256 _lot) internal {
		(bool triggerCancellation, uint256 treasuryEmissions) = auctioneerAuction.finalizeAuction(_lot);

		if (triggerCancellation) {
			cancelAuction(_lot, true);
		}

		if (treasuryEmissions > 0) {
			auctioneerEmissions.transferEmissions(treasury, treasuryEmissions);
		}
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
				msg.sender,
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
