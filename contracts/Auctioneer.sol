// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IWETH } from "./WETH9.sol";
import { IAuctioneerFarm } from "./IAuctioneerFarm.sol";
import "./IAuctioneer.sol";
import { AuctionUtils, AuctionParamsUtils } from "./AuctionUtils.sol";

contract Auctioneer is Ownable, ReentrancyGuard, AuctioneerEvents, IERC721Receiver {
	using SafeERC20 for IERC20;
	using EnumerableSet for EnumerableSet.UintSet;
	using AuctionUtils for Auction;
	using AuctionParamsUtils for AuctionParams;

	// ADMIN

	address public treasury;
	address public farm;
	uint256 public treasurySplit = 2000;
	address public burnAddress = 0x000000000000000000000000000000000000dEaD;
	uint256 public earlyHarvestTax = 5000;

	// CORE

	bool public initialized = false;
	IWETH public WETH;
	address public ETH = address(0);

	uint256 public lotCount;
	mapping(uint256 => Auction) public auctions;
	mapping(uint256 => mapping(uint8 => BidWindow)) public auctionBidWindows;
	mapping(uint256 => mapping(address => AuctionUser)) public auctionUsers;
	mapping(address => EnumerableSet.UintSet) internal userClaimableLots;
	uint256 public startTimestamp;
	uint256 public epochDuration = 90 days;
	uint256 public emissionTaxDuration = 30 days;
	mapping(address => string) public userAlias;
	mapping(string => address) public aliasUser;

	mapping(uint256 => uint256) public auctionsPerDay;
	mapping(uint256 => uint256) public dailyCumulativeEmissionBP;

	// BID PARAMS
	IERC20 public USD;
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

	// GAS SAVINGS
	mapping(address => uint256) public userFunds;

	constructor(
		IERC20 _usd,
		IERC20 _go,
		IWETH _weth,
		uint256 _bidCost,
		uint256 _bidIncrement,
		uint256 _startingBid,
		uint256 _privateRequirement
	) Ownable(msg.sender) {
		USD = _usd;
		GO = _go;
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
		if (_startingBid < 5e17 || _startingBid > 2e18) revert Invalid();
		startingBid = _startingBid;
		emit UpdatedStartingBid(_startingBid);
	}

	// Will not update the bid cost of any already created auctions
	function updateBidCost(uint256 _bidCost) public onlyOwner {
		if (_bidCost < 5e17 || _bidCost > 2e18) revert Invalid();
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
			bal += IAuctioneerFarm(farm).getUserStakedGOBalance(_user);
		}
	}

	function _getUserPrivateAuctionPermitted(address _user) internal view returns (bool) {
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
		auction.claimed = false;
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
		auction.bidData.sum = 0;
		auction.bidData.bids = 0;
		auction.bidData.bid = startingBid;
		auction.bidData.bidTimestamp = _params.unlockTimestamp;
		auction.bidData.bidUser = msg.sender;
		auction.bidData.nextBidBy = auction.getNextBidBy();

		// Frozen bidCost to prevent a change from messing up revenue calculations
		auction.bidData.bidCost = bidCost;

		lotCount++;
		emit AuctionCreated(lot);
	}

	// CANCEL

	function cancelAuction(uint256 _lot, bool _unwrapETH) public validAuctionLot(_lot) nonReentrant onlyOwner {
		Auction storage auction = auctions[_lot];
		uint256 day = _getDayOfTimestamp(auction.unlockTimestamp);

		// Cannot cancel already cancelled auction
		if (auction.finalized) revert NotCancellable();

		// Can only cancel the auction if it doesn't have any bids yet
		if (auction.bidData.bids > 0) revert NotCancellable();

		auction.transferLotTo(treasury, _unwrapETH, ETH, address(WETH));

		// Return emissions to epoch of auction
		uint256 epoch = _getEpochAtTimestamp(auction.unlockTimestamp);
		// Prevent array out of bounds
		if (epoch < 8) {
			epochEmissionsRemaining[epoch] += (auction.emissions.biddersEmission + auction.emissions.treasuryEmission);
			auction.emissions.biddersEmission = 0;
			auction.emissions.treasuryEmission = 0;
		}

		auctionsPerDay[day] -= 1;
		dailyCumulativeEmissionBP[day] -= auction.emissions.bp;
		auction.emissions.bp = 0;

		// Finalize to prevent bidding and claiming
		auction.claimed = true;
		auction.finalized = true;
		emit AuctionCancelled(_lot, msg.sender);
	}

	// BID

	function bid(uint256 _lot, uint256 _multibid, bool _forceWallet) public validAuctionLot(_lot) nonReentrant {
		if (_multibid == 0) revert MustBidAtLeastOnce();
		Auction storage auction = auctions[_lot];
		auction.validateBiddingOpen();

		// VALIDATE: User can participate in auction
		if (auction.isPrivate && !_getUserPrivateAuctionPermitted(msg.sender)) revert PrivateAuction();

		// Update auction with new bid
		auction.bidData.bid += bidIncrement * _multibid;
		auction.bidData.bidUser = msg.sender;
		auction.bidData.bidTimestamp = block.timestamp;
		auction.bidData.sum += auction.bidData.bidCost * _multibid;
		auction.bidData.bids += _multibid;
		auction.bidData.nextBidBy = auction.getNextBidBy();

		// Give user bid point
		auctionUsers[_lot][msg.sender].bids += _multibid;

		// A single bid guarantees emissions, add the lot to a list of the users lots that have claimable emissions
		userClaimableLots[msg.sender].add(_lot);
		if (!_forceWallet && userFunds[msg.sender] > (auction.bidData.bidCost * _multibid)) {
			userFunds[msg.sender] -= (auction.bidData.bidCost * _multibid);
		} else {
			USD.safeTransferFrom(msg.sender, address(this), (auction.bidData.bidCost * _multibid));
		}

		emit Bid(_lot, msg.sender, _multibid, auction.bidData.bid, userAlias[msg.sender]);
	}

	// CLAIM

	function claimAuctionLot(uint256 _lot, bool _forceWallet, bool _unwrapETH) public validAuctionLot(_lot) nonReentrant {
		Auction storage auction = auctions[_lot];

		auction.validateEnded();

		_claimLotWinnings(auction, _forceWallet, _unwrapETH);
		_finalizeAuction(auction);
	}

	// Allows the auction to be finalized without waiting for winner to claim their lot
	function finalizeAuction(uint256 _lot) public validAuctionLot(_lot) nonReentrant {
		Auction storage auction = auctions[_lot];

		auction.validateEnded();

		_finalizeAuction(auction);
	}

	function _claimLotWinnings(Auction storage auction, bool _forceWallet, bool _unwrapETH) internal {
		// User is not winner
		if (msg.sender != auction.bidData.bidUser) revert NotWinner();

		// Winner has already paid for and claimed the lot
		if (auction.claimed) revert AuctionLotAlreadyClaimed();

		// Transfer lot to last bidder (this comes first so it shows up first in explorer)
		auction.transferLotTo(auction.bidData.bidUser, _unwrapETH, ETH, address(WETH));

		// Pay for lot
		if (!_forceWallet && userFunds[msg.sender] >= auction.bidData.bid) {
			// Pay for lot from pre-deposited balance
			userFunds[msg.sender] -= auction.bidData.bid;
		} else if (!_forceWallet && userFunds[msg.sender] > 0) {
			// Pay for lot from mixed
			USD.safeTransferFrom(msg.sender, address(this), auction.bidData.bid - userFunds[msg.sender]);
			userFunds[msg.sender] = 0;
		} else {
			// Pay for lot entirely from wallet
			USD.safeTransferFrom(msg.sender, address(this), auction.bidData.bid);
		}

		// Distribute payment
		auction.distributeLotProfit(USD, auction.bidData.bid, treasury, farm, treasurySplit);

		// Mark Claimed
		auction.claimed = true;
		emit AuctionLotClaimed(auction.lot, msg.sender, auction.rewards.tokens, auction.rewards.nfts);
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

	function claimAuctionEmissions(uint256[] memory _lots) public nonReentrant {
		for (uint256 i = 0; i < _lots.length; i++) {
			_claimAuctionEmissions(_lots[i]);
		}
	}

	function _claimAuctionEmissions(uint256 _lot) public validAuctionLot(_lot) {
		Auction storage auction = auctions[_lot];
		AuctionUser storage user = auctionUsers[auction.lot][msg.sender];

		auction.validateEnded();

		// Exit if user already claimed emissions from auction
		if (user.claimed) return;

		// Exit early if nothing to claim
		if (user.bids == 0) return;

		// If emissions should be taxed
		bool incursTax = block.timestamp < (auction.day * 1 days) + emissionTaxDuration;

		// Calculate emission amounts
		uint256 emissions = (auction.emissions.biddersEmission * user.bids) / auction.bidData.bids;
		uint256 userEmissions = (emissions * (incursTax ? (10000 - earlyHarvestTax) : 10000)) / 10000;
		uint256 burnEmissions = emissions - userEmissions;

		// Transfer emissions
		GO.safeTransfer(msg.sender, userEmissions);
		if (burnEmissions > 0) {
			GO.safeTransfer(burnAddress, (emissions * earlyHarvestTax) / 10000);
		}
		// Mark claimed
		user.claimed = true;
		userClaimableLots[msg.sender].remove(_lot); // Remove from list of lots with emissions still to claim
		emit UserClaimedLotEmissions(auction.lot, msg.sender, userEmissions, burnEmissions);
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

	function getBidsData(
		address _user,
		uint256 _lot
	) public view validAuctionLot(_lot) returns (uint256 userBids, uint256 auctionBids) {
		userBids = auctionUsers[_lot][_user].bids;
		auctionBids = auctions[_lot].bidData.bids;
	}

	function getAuction(uint256 _lot) public view validAuctionLot(_lot) returns (Auction memory) {
		return auctions[_lot];
	}

	function getAuctionUser(uint256 _lot, address _user) public view validAuctionLot(_lot) returns (AuctionUser memory) {
		return auctionUsers[_lot][_user];
	}

	function getAuctionTokenEarned(address _user, uint256 _lot) public view validAuctionLot(_lot) returns (uint256) {
		// Prevent div by 0
		if (auctionUsers[_lot][_user].bids == 0 || auctions[_lot].bidData.bids == 0) return 0;

		return (auctionUsers[_lot][_user].bids * auctions[_lot].emissions.biddersEmission) / auctions[_lot].bidData.bids;
	}

	function getUserClaimableLots(address _user) public view returns (uint256[] memory) {
		return userClaimableLots[_user].values();
	}

	function getUserClaimableLotsData(address _user) public view returns (ClaimableLotData[] memory lotDatas) {
		uint256[] memory lots = userClaimableLots[_user].values();
		lotDatas = new ClaimableLotData[](lots.length);

		// Iterate through lots, add data
		for (uint256 i = 0; i < lots.length; i++) {
			lotDatas[i].lot = lots[i];
			lotDatas[i].emissions =
				(auctions[lots[i]].emissions.biddersEmission * auctionUsers[lots[i]][_user].bids) /
				auctions[lots[i]].bidData.bids;
			lotDatas[i].day = auctions[lots[i]].day;

			uint256 maturesAtTimestamp = (lotDatas[i].day * 1 days) + emissionTaxDuration;
			lotDatas[i].timeUntilMature = block.timestamp >= maturesAtTimestamp ? 0 : maturesAtTimestamp - block.timestamp;
		}
	}

	function getCurrentEpochData() public view returns (EpochData memory epochData) {
		return _getEpochDataAtTimestamp(block.timestamp);
	}
}
