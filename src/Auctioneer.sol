// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IWETH } from "./WETH9.sol";
import { IAuctioneerFarm } from "./IAuctioneerFarm.sol";
import "./IAuctioneer.sol";
import { BlastYield } from "./BlastYield.sol";
import { DecUtils, AuctionUtils, AuctionParamsUtils } from "./AuctionUtils.sol";

contract Auctioneer is Ownable, ReentrancyGuard, AuctioneerEvents, IERC721Receiver, BlastYield {
	using DecUtils for uint256;
	using SafeERC20 for IERC20;
	using EnumerableSet for EnumerableSet.UintSet;
	using AuctionUtils for Auction;
	using AuctionParamsUtils for AuctionParams;

	// ADMIN

	address public treasury;
	address public farm;
	uint256 public treasurySplit = 2000;
	uint256 public earlyHarvestTax = 5000;
	address public deadAddress = 0x000000000000000000000000000000000000dEaD;

	// CORE

	bool public initialized = false;
	IWETH public WETH;
	address public ETH = address(0);

	uint256 public lotCount;
	mapping(uint256 => Auction) public auctions;
	mapping(uint256 => mapping(uint8 => BidWindow)) public auctionBidWindows;
	mapping(uint256 => mapping(address => AuctionUser)) public auctionUsers;
	mapping(address => EnumerableSet.UintSet) internal userInteractedLots;
	mapping(address => EnumerableSet.UintSet) internal userUnharvestedLots;
	uint256 public startTimestamp;
	uint256 public epochDuration = 90 days;
	uint256 public emissionTaxDuration = 30 days;
	mapping(address => string) public userAlias;
	mapping(string => address) public aliasUser;

	mapping(uint256 => uint256) public auctionsPerDay;
	mapping(uint256 => uint256) public dailyCumulativeEmissionBP;

	// BID PARAMS
	IERC20 public USD;
	uint8 public usdDecimals;
	uint256 public bidIncrement;
	uint256 public startingBid;
	uint256 public privateAuctionRequirement;
	uint256 public bidCost;
	uint256 public onceTwiceBlastBonusTime = 9;

	// EMISSIONS
	IERC20 public GO;
	uint256[8] public emissionSharePerEpoch = [128, 64, 32, 16, 8, 4, 2, 1];
	uint256 public emissionSharesTotal = 255;
	uint256 public emissionPerShare = 255e18;
	uint256[8] public epochEmissionsRemaining = [0, 0, 0, 0, 0, 0, 0, 0];

	// FREE BIDS using VOUCHERS
	IERC20 public VOUCHER;

	// GAS SAVINGS
	mapping(address => uint256) public userFunds;

	constructor(
		IERC20 _usd,
		IERC20 _go,
		IERC20 _voucher,
		IWETH _weth,
		uint256 _bidCost,
		uint256 _bidIncrement,
		uint256 _startingBid,
		uint256 _privateRequirement
	) Ownable(msg.sender) {
		USD = _usd;
		usdDecimals = IERC20Metadata(address(_usd)).decimals();
		GO = _go;
		VOUCHER = _voucher;
		WETH = _weth;
		bidCost = _bidCost;
		bidIncrement = _bidIncrement;
		startingBid = _startingBid;
		privateAuctionRequirement = _privateRequirement;
	}

	// RECEIVERS

	receive() external payable {}

	function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
		return this.onERC721Received.selector;
	}

	// MODIFIERS

	modifier validAuctionLot(uint256 _lot) {
		if (_lot >= lotCount) revert InvalidAuctionLot();
		_;
	}

	modifier validRune(uint256 _lot, uint8 _rune) {
		if (auctions[_lot].runes.length > 0 && (_rune == 0 || _rune >= auctions[_lot].runes.length)) revert InvalidRune();
		if (auctions[_lot].runes.length == 0 && _rune != 0) revert InvalidRune();
		_;
	}

	modifier validUserRuneSelection(uint256 _lot, uint8 _rune) {
		if (auctionUsers[_lot][msg.sender].rune != 0 && auctionUsers[_lot][msg.sender].rune != _rune)
			revert CantSwitchRune();
		_;
	}

	///////////////////
	// ADMIN
	///////////////////

	function setTreasury(address _treasury) public onlyOwner {
		if (_treasury == address(0)) revert ZeroAddress();
		treasury = _treasury;
		emit UpdatedTreasury(_treasury);
	}

	function setFarm(address _farm) public onlyOwner {
		farm = _farm;
		emit UpdatedFarm(_farm);
	}

	function setTreasurySplit(uint256 _treasurySplit) public onlyOwner {
		if (_treasurySplit > 5000) revert TooSteep();
		treasurySplit = _treasurySplit;
		emit UpdatedTreasurySplit(_treasurySplit);
	}

	function updatePrivateAuctionRequirement(uint256 _requirement) public onlyOwner {
		privateAuctionRequirement = _requirement;
		emit UpdatedPrivateAuctionRequirement(_requirement);
	}

	function updateStartingBid(uint256 _startingBid) public onlyOwner {
		// Must be between 0.5 and 2 usd
		if (
			_startingBid < uint256(0.5e18).transformDec(18, usdDecimals) ||
			_startingBid > uint256(2e18).transformDec(18, usdDecimals)
		) revert Invalid();
		startingBid = _startingBid;
		emit UpdatedStartingBid(_startingBid);
	}

	// Will not update the bid cost of any already created auctions
	function updateBidCost(uint256 _bidCost) public onlyOwner {
		// Must be between 0.5 and 2 usd
		if (
			_bidCost < uint256(0.5e18).transformDec(18, usdDecimals) || _bidCost > uint256(2e18).transformDec(18, usdDecimals)
		) revert Invalid();
		bidCost = _bidCost;
		emit UpdatedBidCost(_bidCost);
	}

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

	///////////////////
	// INITIALIZATION
	///////////////////

	function distributeEmissionsBetweenEpochs() internal {
		uint256 totalToEmit = GO.balanceOf(address(this));
		for (uint8 i = 0; i < 8; i++) {
			epochEmissionsRemaining[i] = (totalToEmit * emissionSharePerEpoch[i]) / emissionSharesTotal;
		}
	}

	function initializeAuctions(uint256 _unlockTimestamp) internal {
		startTimestamp = _unlockTimestamp;
		distributeEmissionsBetweenEpochs();
	}

	function initialize(uint256 _unlockTimestamp) public onlyOwner {
		if (GO.balanceOf(address(this)) == 0) revert GONotYetReceived();
		if (initialized) revert AlreadyInitialized();
		initializeAuctions(_unlockTimestamp);
		initialized = true;
		emit Initialized();
	}

	///////////////////
	// BLAST
	///////////////////

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

	///////////////////
	// INTERNAL HELPERS
	///////////////////

	function _getDayOfTimestamp(uint256 timestamp) internal pure returns (uint256 day) {
		return timestamp / 1 days;
	}

	function _getCurrentDay() internal view returns (uint256 day) {
		return _getDayOfTimestamp(block.timestamp);
	}

	function _getEpochAtTimestamp(uint256 timestamp) internal view returns (uint256 epoch) {
		if (startTimestamp == 0 || timestamp < startTimestamp) return 0;
		epoch = (timestamp - startTimestamp) / epochDuration;
	}

	function _getEpochDataAtTimestamp(uint256 timestamp) internal view returns (EpochData memory epochData) {
		epochData.epoch = _getEpochAtTimestamp(timestamp);

		epochData.start = epochData.epoch * epochDuration;
		epochData.end = (epochData.epoch + 1) * epochDuration;

		if (timestamp > epochData.end) {
			epochData.daysRemaining = 0;
		} else {
			epochData.daysRemaining = ((epochData.end - timestamp) / 1 days) + 1;
		}

		// Emissions only exist for first 8 epochs, prevent array out of bounds
		epochData.emissionsRemaining = epochData.epoch >= 8 ? 0 : epochEmissionsRemaining[epochData.epoch];

		epochData.dailyEmission = (epochData.emissionsRemaining == 0 || epochData.daysRemaining == 0)
			? 0
			: epochData.emissionsRemaining / epochData.daysRemaining;
	}

	function _getEmissionForAuction(uint256 _unlockTimestamp, uint256 _bp) internal view returns (uint256) {
		EpochData memory epochData = _getEpochDataAtTimestamp(_unlockTimestamp);
		if (epochData.dailyEmission == 0) return 0;

		// Modulate with auction _bp (percent of daily emission)
		epochData.dailyEmission = (epochData.dailyEmission * _bp) / 10000;

		// Check to prevent stealing emissions from next epoch
		//  (would only happen if it's the last day of the epoch and _bp > 10000)
		if (epochData.dailyEmission > epochData.emissionsRemaining) {
			return epochData.emissionsRemaining;
		}

		return epochData.dailyEmission;
	}

	function _userGOBalance(address _user) internal view returns (uint256 bal) {
		bal = GO.balanceOf(_user);
		if (farm != address(0)) {
			bal += IAuctioneerFarm(farm).getEqualizedUserStaked(_user);
		}
	}

	function _getUserPrivateAuctionsPermitted(address _user) internal view returns (bool) {
		return _userGOBalance(_user) >= privateAuctionRequirement;
	}

	///////////////////
	// CORE
	///////////////////

	// CREATE

	function createDailyAuctions(AuctionParams[] memory _params) public onlyOwner nonReentrant {
		if (!initialized) revert NotInitialized();
		if (treasury == address(0)) revert TreasuryNotSet();

		for (uint8 i = 0; i < _params.length; i++) {
			_createSingleAuction(_params[i], i);
		}
	}

	function _validateAuctionParams(AuctionParams memory _params) internal view {
		_params.validateUnlock();
		_params.validateTokens();
		_params.validateNFTs();
		_params.validateAnyReward();
		_params.validateBidWindows();
		_params.validateRunes();
	}

	function _validateAuctionDay(AuctionParams memory _params, uint256 _paramIndex) internal view {
		uint256 day = _getDayOfTimestamp(_params.unlockTimestamp);

		// Check that no more than 4 auctions take place per day
		if ((auctionsPerDay[day] + 1) > 4) revert TooManyAuctionsPerDay(_paramIndex);

		// Check that days emission doesn't exceed allowable bonus (30000)
		// Most days, the emission will be 10000
		// An emission BP over 10000 means it is using emissions scheduled for other days
		// Auction emissions for the remainder of the epoch will be reduced
		// This will never overflow the emissions though, because the emission amount is calculated from remaining emissions
		if ((dailyCumulativeEmissionBP[day] + _params.emissionBP) > 30000)
			revert InvalidDailyEmissionBP(dailyCumulativeEmissionBP[day], _params.emissionBP, _paramIndex);
	}

	function _createSingleAuction(AuctionParams memory _params, uint256 _paramIndex) internal {
		_validateAuctionParams(_params);
		_validateAuctionDay(_params, _paramIndex);

		// Update daily attributes
		uint256 lot = lotCount;
		uint256 day = _getDayOfTimestamp(_params.unlockTimestamp);
		auctionsPerDay[day] += 1;
		dailyCumulativeEmissionBP[day] += _params.emissionBP;

		Auction storage auction = auctions[lot];

		// Base data
		auction.lot = lot;
		auction.day = day;
		auction.name = _params.name;
		auction.isPrivate = _params.isPrivate;
		auction.unlockTimestamp = _params.unlockTimestamp;
		auction.addBidWindows(_params, onceTwiceBlastBonusTime);
		auction.finalized = false;

		// Rewards
		auction.addRewards(_params);
		auction.transferLotFrom(treasury, ETH, address(WETH));

		// Emissions
		uint256 epoch = _getEpochAtTimestamp(_params.unlockTimestamp);
		uint256 totalEmission = _getEmissionForAuction(_params.unlockTimestamp, _params.emissionBP);
		// Only emit during first 8 epochs
		if (epoch < 8 && totalEmission > 0) {
			// Validated not to underflow in _getEmissionForAuction
			epochEmissionsRemaining[epoch] -= totalEmission;
			auction.emissions.bp = _params.emissionBP;
			auction.emissions.biddersEmission = (totalEmission * 90) / 100;
			auction.emissions.treasuryEmission = (totalEmission * 10) / 100;
		}

		// Initial bidding data
		auction.bidData.revenue = 0;
		auction.bidData.bids = 0;
		auction.bidData.bid = startingBid;
		auction.bidData.bidTimestamp = _params.unlockTimestamp;
		auction.bidData.bidUser = msg.sender;
		auction.bidData.nextBidBy = auction.getNextBidBy();
		auction.bidData.usdDecimals = usdDecimals;

		// Runes
		auction.addRunes(_params);

		// Frozen bidCost to prevent a change from messing up revenue calculations
		auction.bidData.bidCost = bidCost;

		lotCount++;
		emit AuctionCreated(lot);
	}

	// CANCEL

	function cancelAuction(uint256 _lot, bool _unwrapETH) public validAuctionLot(_lot) nonReentrant onlyOwner {
		Auction storage auction = auctions[_lot];

		// Auction only cancellable if it doesn't have any bids, or if its already been finalized
		if (auction.bidData.bids > 0 || auction.finalized) revert NotCancellable();

		// Transfer lot tokens and nfts back to treasury
		auction.transferLotTo(treasury, 1e18, _unwrapETH, ETH, address(WETH));

		// Return emissions to epoch of auction
		uint256 epoch = _getEpochAtTimestamp(auction.unlockTimestamp);
		// Prevent array out of bounds
		if (epoch < 8) {
			epochEmissionsRemaining[epoch] += (auction.emissions.biddersEmission + auction.emissions.treasuryEmission);
			auction.emissions.biddersEmission = 0;
			auction.emissions.treasuryEmission = 0;
		}

		uint256 day = _getDayOfTimestamp(auction.unlockTimestamp);
		auctionsPerDay[day] -= 1;
		dailyCumulativeEmissionBP[day] -= auction.emissions.bp;
		auction.emissions.bp = 0;

		// Finalize to prevent bidding and claiming lot
		auction.finalized = true;
		emit AuctionCancelled(_lot, msg.sender);
	}

	// BID

	function bid(
		uint256 _lot,
		BidOptions memory _options
	)
		public
		validAuctionLot(_lot)
		validRune(_lot, _options.rune)
		validUserRuneSelection(_lot, _options.rune)
		nonReentrant
	{
		Auction storage auction = auctions[_lot];
		AuctionUser storage user = auctionUsers[_lot][msg.sender];
		auction.validateBiddingOpen();

		// Always bid at least once
		if (_options.multibid == 0) _options.multibid = 1;

		// VALIDATE: User can participate in auction
		if (auction.isPrivate && !_getUserPrivateAuctionsPermitted(msg.sender)) revert PrivateAuction();

		// Update auction with new bid
		auction.bidData.bid += bidIncrement * _options.multibid;
		auction.bidData.bidUser = msg.sender;
		auction.bidData.bidTimestamp = block.timestamp;
		if (_options.paymentType != BidPaymentType.VOUCHER) {
			auction.bidData.revenue += auction.bidData.bidCost * _options.multibid;
		}
		auction.bidData.bids += _options.multibid;
		auction.bidData.nextBidBy = auction.getNextBidBy();

		// Give user bid point
		user.bids += _options.multibid;

		// Runes
		if (auction.hasRunes()) {
			// If user hasn't selected rune, select it, and add 1 to rune's user count
			if (user.rune == 0) {
				user.rune = _options.rune;
				auction.runes[user.rune].users += 1;
			}

			// Add bids to rune, used for calculating emissions
			auction.runes[user.rune].bids += _options.multibid;

			// Mark bidRune
			auction.bidData.bidRune = user.rune;
		}

		// Mark lot as unharvested if it has emissions
		if (auction.emissions.biddersEmission > 0) {
			userUnharvestedLots[msg.sender].add(_lot);
		}

		// Mark user interacted with lot
		userInteractedLots[msg.sender].add(_lot);

		// Pay for bid
		if (_options.paymentType == BidPaymentType.WALLET) {
			USD.safeTransferFrom(msg.sender, address(this), (auction.bidData.bidCost * _options.multibid));
		}
		if (_options.paymentType == BidPaymentType.FUNDS) {
			if (userFunds[msg.sender] < auction.bidData.bidCost * _options.multibid) revert InsufficientFunds();
			userFunds[msg.sender] -= (auction.bidData.bidCost * _options.multibid);
		}
		if (_options.paymentType == BidPaymentType.VOUCHER) {
			VOUCHER.safeTransferFrom(msg.sender, deadAddress, _options.multibid * 1e18);
		}

		emit Bid(_lot, msg.sender, auction.bidData.bid, userAlias[msg.sender], _options);
	}

	// CLAIM

	function claimAuctionLot(uint256 _lot, ClaimLotOptions memory _options) public validAuctionLot(_lot) nonReentrant {
		Auction storage auction = auctions[_lot];

		auction.validateEnded();

		_claimLotWinnings(auction, _options);
		_finalizeAuction(auction);
	}

	function _validateUserIsWinner(Auction storage auction) internal view returns (bool) {
		if (auction.hasRunes()) {
			return auctionUsers[auction.lot][msg.sender].rune == auction.bidData.bidRune;
		}
		return msg.sender == auction.bidData.bidUser;
	}

	function _getUserShareOfLot(Auction storage auction, AuctionUser storage user) internal view returns (uint256) {
		if (auction.hasRunes()) {
			return (user.bids * 1e18) / auction.runes[user.rune].bids;
		}
		return 1e18;
	}

	function _claimLotWinnings(Auction storage auction, ClaimLotOptions memory _options) internal {
		// User is not winner
		if (!_validateUserIsWinner(auction)) revert NotWinner();

		AuctionUser storage user = auctionUsers[auction.lot][msg.sender];

		// Winner has already paid for and claimed the lot (or their share of it)
		if (user.lotClaimed) revert UserAlreadyClaimedLot();

		uint256 userShareOfLot = _getUserShareOfLot(auction, user);
		uint256 userShareOfPayment = (auction.bidData.bid * userShareOfLot) / 1e18;

		// Transfer lot to last bidder (this comes first so it shows up first in explorer)
		auction.transferLotTo(msg.sender, userShareOfLot, _options.unwrapETH, ETH, address(WETH));

		// Pay for lot
		if (_options.paymentType == LotPaymentType.FUNDS) {
			if (userFunds[msg.sender] < userShareOfPayment) revert InsufficientFunds();
			userFunds[msg.sender] -= userShareOfPayment;
		}
		if (_options.paymentType == LotPaymentType.WALLET) {
			USD.safeTransferFrom(msg.sender, address(this), userShareOfPayment);
		}

		// Distribute payment
		auction.distributeLotProfit(USD, userShareOfPayment, treasury, farm, treasurySplit);

		// Mark Claimed
		user.lotClaimed = true;

		emit UserClaimedLot(
			auction.lot,
			msg.sender,
			user.rune,
			userShareOfLot,
			auction.rewards.tokens,
			auction.rewards.nfts
		);
	}

	// FINALIZE

	// Allows the auction to be finalized without waiting for a winner to claim their lot
	function finalizeAuction(uint256 _lot) public validAuctionLot(_lot) nonReentrant {
		Auction storage auction = auctions[_lot];

		auction.validateEnded();

		_finalizeAuction(auction);
	}

	function _finalizeAuction(Auction storage auction) internal {
		// Exit if already finalized
		if (auction.finalized) return;

		// Refund lot to treasury
		auction.distributeLotRevenue(USD, treasury, farm, treasurySplit);

		// Send emissions to treasury
		if (auction.emissions.treasuryEmission > 0) {
			GO.safeTransfer(treasury, auction.emissions.treasuryEmission);
		}

		// Mark Finalized
		auction.finalized = true;
		emit AuctionFinalized(auction.lot);
	}

	// HARVEST

	function harvestAuctionEmissions(uint256[] memory _lots) public nonReentrant {
		for (uint256 i = 0; i < _lots.length; i++) {
			_harvestAuctionEmissions(_lots[i]);
		}
	}

	function _harvestAuctionEmissions(uint256 _lot) internal validAuctionLot(_lot) {
		Auction storage auction = auctions[_lot];
		AuctionUser storage user = auctionUsers[auction.lot][msg.sender];

		auction.validateEnded();

		// Exit if user already harvested emissions from auction
		if (user.emissionsHarvested) return;

		// Exit early if nothing to claim
		if (user.bids == 0) return;

		// If emissions should be taxed
		bool incursTax = block.timestamp < (auction.day * 1 days) + emissionTaxDuration;

		// Calculate emission amounts
		uint256 emissions = (auction.emissions.biddersEmission * user.bids) / auction.bidData.bids;
		user.harvestedEmissions = (emissions * (incursTax ? (10000 - earlyHarvestTax) : 10000)) / 10000;
		user.burnedEmissions = emissions - user.harvestedEmissions;

		// Transfer emissions
		GO.safeTransfer(msg.sender, user.harvestedEmissions);
		if (user.burnedEmissions > 0) {
			GO.safeTransfer(deadAddress, user.burnedEmissions);
		}

		// Mark harvested
		user.emissionsHarvested = true;
		userUnharvestedLots[msg.sender].remove(_lot);

		emit UserHarvestedLotEmissions(auction.lot, msg.sender, user.harvestedEmissions, user.burnedEmissions);
	}

	///////////////////
	// USER
	///////////////////

	function setAlias(string memory _alias) public {
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

	function addFunds(uint256 _amount) public nonReentrant {
		if (_amount > USD.balanceOf(msg.sender)) revert BadDeposit();

		USD.safeTransferFrom(msg.sender, address(this), _amount);
		userFunds[msg.sender] += _amount;

		emit AddedFunds(msg.sender, _amount);
	}

	function withdrawFunds(uint256 _amount) public nonReentrant {
		if (_amount > userFunds[msg.sender]) revert BadWithdrawal();

		USD.safeTransfer(msg.sender, _amount);
		userFunds[msg.sender] -= _amount;

		emit WithdrewFunds(msg.sender, _amount);
	}

	///////////////////
	// VIEW
	///////////////////

	function getAuction(uint256 _lot) public view validAuctionLot(_lot) returns (Auction memory) {
		return auctions[_lot];
	}

	function getUserPrivateAuctionsPermitted(address _user) public view returns (bool) {
		return _getUserPrivateAuctionsPermitted(_user);
	}

	function getAuctionUser(uint256 _lot, address _user) public view validAuctionLot(_lot) returns (AuctionUser memory) {
		return auctionUsers[_lot][_user];
	}

	function getUserInteractedLots(address _user) public view returns (uint256[] memory) {
		return userInteractedLots[_user].values();
	}

	function getUserUnharvestedLots(address _user) public view returns (uint256[] memory) {
		return userUnharvestedLots[_user].values();
	}

	function getUserLotInfo(uint256 _lot, address _user) public view returns (UserLotInfo memory info) {
		Auction memory auction = auctions[_lot];
		AuctionUser memory user = auctionUsers[_lot][_user];

		info.lot = auction.lot;
		info.rune = user.rune;

		// Bids
		info.bidCounts.user = user.bids;
		info.bidCounts.rune = auction.runes.length == 0 || user.rune == 0 ? 0 : auction.runes[user.rune].bids;
		info.bidCounts.auction = auction.bidData.bids;

		// Emissions
		info.matureTimestamp = (auction.day * 1 days) + emissionTaxDuration;
		info.timeUntilMature = block.timestamp >= info.matureTimestamp ? 0 : info.matureTimestamp - block.timestamp;
		info.emissionsEarned = user.bids == 0 || auction.bidData.bids == 0
			? 0
			: (user.bids * auction.emissions.biddersEmission) / auction.bidData.bids;

		info.emissionsHarvested = user.emissionsHarvested;
		info.harvestedEmissions = user.harvestedEmissions;
		info.burnedEmissions = user.burnedEmissions;

		// Winning bid
		info.isWinner = auction.runes.length > 0 ? user.rune == auction.bidData.bidRune : _user == auction.bidData.bidUser;
		info.lotClaimed = user.lotClaimed;
	}

	function getCurrentEpochData() public view returns (EpochData memory epochData) {
		return _getEpochDataAtTimestamp(block.timestamp);
	}
}
