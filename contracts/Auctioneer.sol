// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IWETH } from "./WETH9.sol";
import { IAuctioneerFarm } from "./IAuctioneerFarm.sol";
import "./IAuctioneer.sol";
import { AuctionUtils, AuctionParamsUtils } from "./AuctionUtils.sol";

contract Auctioneer is Ownable, ReentrancyGuard, AuctioneerEvents {
	using SafeERC20 for IERC20;
	using AuctionUtils for Auction;
	using AuctionParamsUtils for AuctionParams;

	// CORE

	bool public initialized = false;
	IWETH public WETH;
	address public ETH = address(0);

	uint256 public lotCount;
	mapping(uint256 => Auction) public auctions;
	mapping(uint256 => mapping(uint8 => BidWindow)) public auctionBidWindows;
	mapping(uint256 => mapping(address => AuctionUser)) public auctionUsers;
	uint256 public startTimestamp;
	uint256 public epochDuration = 90 days;
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
	mapping(address => uint256) public userBalance;

	address public treasury;
	address public farm;
	uint256 public treasurySplit = 5000;

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

	// Fallback
	receive() external payable {}

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

	function _getDayOfTimestamp(uint256 timestamp) internal view returns (uint256 day) {
		return timestamp / 1 days;
	}

	function _getEpochAtTimestamp(uint256 timestamp) internal view returns (uint256 epoch) {
		if (startTimestamp == 0 || timestamp < startTimestamp) return 0;
		epoch = (timestamp - startTimestamp) / epochDuration;
	}

	function _getEpochDataAtTimestamp(
		uint256 timestamp
	)
		internal
		view
		returns (
			uint256 epoch,
			uint256 start,
			uint256 end,
			uint256 daysRemaining,
			uint256 emissionsRemaining,
			uint256 dailyEmission
		)
	{
		epoch = _getEpochAtTimestamp(timestamp);

		start = epoch * epochDuration;
		end = (epoch + 1) * epochDuration;

		if (timestamp > end) {
			daysRemaining = 0;
		} else {
			daysRemaining = ((end - timestamp) / 1 days) + 1;
		}

		// Emissions only exist for first 8 epochs, prevent array out of bounds
		emissionsRemaining = epoch >= 8 ? 0 : epochEmissionsRemaining[epoch];

		dailyEmission = (emissionsRemaining == 0 || daysRemaining == 0) ? 0 : emissionsRemaining / daysRemaining;
	}

	function _getEmissionForAuction(uint256 _unlockTimestamp, uint256 _bp) internal view returns (uint256) {
		(, , , , uint256 emissionsRemaining, uint256 dailyEmission) = _getEpochDataAtTimestamp(_unlockTimestamp);
		if (dailyEmission == 0) return 0;

		// Modulate with auction _bp (percent of daily emission)
		dailyEmission = (dailyEmission * _bp) / 10000;

		// Check to prevent stealing emissions from next epoch
		//  (would only happen if it's the last day of the epoch and _bp > 10000)
		if (dailyEmission > emissionsRemaining) {
			return emissionsRemaining;
		}

		return dailyEmission;
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

	function _getDistributionAmounts(
		uint256 _toDistribute
	) internal view returns (uint256 treasuryDistribution, uint256 farmDistribution) {
		// Calculate distributions
		treasuryDistribution = (_toDistribute * treasurySplit) / 10000;
		farmDistribution = _toDistribute - treasuryDistribution;

		// Add unused farm distribution to treasury (if no farm set, send all funds to treasury)
		if (farm == address(0)) {
			treasuryDistribution += farmDistribution;
			farmDistribution = 0;
		}
	}

	function _distributeUSD(uint256 _amount) internal {
		// Calculate distributions
		(uint256 treasuryDistribution, uint256 farmDistribution) = _getDistributionAmounts(_amount);

		// Distribute
		if (treasuryDistribution > 0) {
			USD.safeTransfer(treasury, treasuryDistribution);
		}

		// If farm not set, farm distribution will be 0
		if (farmDistribution > 0) {
			USD.safeTransfer(farm, farmDistribution);
			IAuctioneerFarm(farm).receiveUSDDistribution();
		}
	}

	function _transferLotToken(address _token, address _to, uint256 _amount, bool _shouldUnwrap) internal {
		if (_token == ETH) {
			if (_shouldUnwrap) {
				// If lot token is ETH, it is held in contract as WETH, and needs to be unwrapped before being sent to user
				IWETH(WETH).withdraw(_amount);
				(bool sent, bytes memory data) = _to.call{ value: _amount }("");
				if (!sent) revert ETHTransferFailed();
			} else {
				IERC20(address(WETH)).safeTransfer(_to, _amount);
			}
		} else {
			// Transfer as default ERC20
			IERC20(_token).safeTransfer(_to, _amount);
		}
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

	function _createSingleAuction(AuctionParams memory _params, uint256 _paramIndex) internal {
		_params.validateUnlock();
		_params.validateTokens();
		_params.validateBidWindows();

		uint256 day = _getDayOfTimestamp(_params.unlockTimestamp);

		// Check that no more than 4 auctions take place per day
		if ((auctionsPerDay[day] + 1) > 4) revert TooManyAuctionsPerDay(_paramIndex);
		auctionsPerDay[day] += 1;

		// Check that days emission doesn't exceed allowable bonus (20000)
		// Most days, the emission will be 10000
		// An emission BP over 10000 means it is using emissions scheduled for other days
		// Auction emissions for the remainder of the epoch will be reduced
		// This will never overflow the emissions though, because the emission amount is calculated from remaining emissions
		if ((dailyCumulativeEmissionBP[day] + _params.emissionBP) > 20000)
			revert InvalidDailyEmissionBP(dailyCumulativeEmissionBP[day], _params.emissionBP, _paramIndex);
		dailyCumulativeEmissionBP[day] += _params.emissionBP;

		uint256 lot = lotCount;

		// Transfer tokens from treasury
		for (uint8 i = 0; i < _params.tokens.length; i++) {
			address token = _params.tokens[i] == ETH ? address(WETH) : _params.tokens[i];
			IERC20(token).safeTransferFrom(treasury, address(this), _params.amounts[i]);
		}

		auctions[lot].lot = lot;
		auctions[lot].isPrivate = _params.isPrivate;

		// Emissions
		uint256 epoch = _getEpochAtTimestamp(_params.unlockTimestamp);
		uint256 totalEmission = _getEmissionForAuction(_params.unlockTimestamp, _params.emissionBP);
		// Only emit during first 8 epochs
		if (epoch < 8 && totalEmission > 0) {
			// Validated not to underflow in _getEmissionForAuction
			epochEmissionsRemaining[epoch] -= totalEmission;
			auctions[lot].biddersEmission = (totalEmission * 90) / 100;
			auctions[lot].treasuryEmission = (totalEmission * 10) / 100;
		}

		auctions[lot].addBidWindows(_params, onceTwiceBlastBonusTime);
		auctions[lot].bids = 0;

		auctions[lot].tokens = _params.tokens;
		auctions[lot].amounts = _params.amounts;
		auctions[lot].name = _params.name;
		auctions[lot].unlockTimestamp = _params.unlockTimestamp;

		auctions[lot].sum = 0;
		auctions[lot].bid = startingBid;
		auctions[lot].bidTimestamp = _params.unlockTimestamp;
		auctions[lot].bidUser = msg.sender;

		auctions[lot].claimed = false;
		auctions[lot].finalized = false;

		lotCount++;
		emit AuctionCreated(lot);
	}

	// CANCEL

	function cancelAuction(uint256 _lot, bool _shouldUnwrap) public validAuctionLot(_lot) nonReentrant onlyOwner {
		Auction storage auction = auctions[_lot];

		// Cannot cancel already cancelled auction
		if (auction.finalized) revert NotCancellable();

		// Can only cancel the auction if it doesn't have any bids yet
		if (auction.bids > 0) revert NotCancellable();

		// Return lot to treasury
		for (uint8 i = 0; i < auction.tokens.length; i++) {
			_transferLotToken(auction.tokens[i], treasury, auction.amounts[i], _shouldUnwrap);
		}

		// Return emissions to epoch of auction
		uint256 epoch = _getEpochAtTimestamp(auction.unlockTimestamp);

		// Prevent array out of bounds
		if (epoch < 8) {
			epochEmissionsRemaining[epoch] += (auction.biddersEmission + auction.treasuryEmission);
			auction.biddersEmission = 0;
			auction.treasuryEmission = 0;
		}

		auction.finalize();
		emit AuctionCancelled(_lot, msg.sender);
	}

	// BID

	function bid(uint256 _lot, bool _forceWallet) public validAuctionLot(_lot) nonReentrant {
		Auction storage auction = auctions[_lot];
		auction.validateBiddingOpen();

		// VALIDATE: User can participate in auction
		if (auction.isPrivate && !_getUserPrivateAuctionPermitted(msg.sender)) revert PrivateAuction();

		// Update auction with new bid
		auction.bid += bidIncrement;
		auction.bidUser = msg.sender;
		auction.bidTimestamp = block.timestamp;
		auction.sum += bidCost;

		// Give user bid point
		auction.bids += 1;
		auctionUsers[_lot][msg.sender].bids += 1;

		if (!_forceWallet && userBalance[msg.sender] > bidCost) {
			userBalance[msg.sender] -= bidCost;
		} else {
			USD.safeTransferFrom(msg.sender, address(this), bidCost);
		}

		emit Bid(_lot, msg.sender, auction.bid, userAlias[msg.sender]);
	}

	// CLAIM

	function claimAuction(uint256 _lot, bool _forceWallet, bool _shouldUnwrap) public validAuctionLot(_lot) nonReentrant {
		Auction storage auction = auctions[_lot];

		auction.validateEnded();

		claimLotWinnings(auction, _forceWallet, _shouldUnwrap);
		finalizeAuction(auction);
		claimEmissions(auction);
	}

	function claimLotWinnings(Auction storage auction, bool _forceWallet, bool _shouldUnwrap) internal {
		// Exit if claiming not available
		if (msg.sender != auction.bidUser || auction.claimed) return;

		// Transfer lot to last bidder (this comes first so it shows up first in etherscan)
		for (uint8 i = 0; i < auction.tokens.length; i++) {
			_transferLotToken(auction.tokens[i], auction.bidUser, auction.amounts[i], _shouldUnwrap);
		}

		// Pay for lot from pre-deposited balance
		if (!_forceWallet && userBalance[msg.sender] >= auction.bid) {
			userBalance[msg.sender] -= auction.bid;

			// Pay for lot from mixed
		} else if (!_forceWallet && userBalance[msg.sender] > 0) {
			USD.safeTransferFrom(msg.sender, address(this), auction.bid - userBalance[msg.sender]);
			userBalance[msg.sender] = 0;

			// Pay for lot entirely from wallet
		} else {
			USD.safeTransferFrom(msg.sender, address(this), auction.bid);
		}

		// Distribute payment
		_distributeUSD(auction.bid);

		// Mark Claimed
		auction.claimed = true;
		emit AuctionLotClaimed(auction.lot, msg.sender, auction.tokens, auction.amounts);
	}

	function finalizeAuction(Auction storage auction) internal {
		// Exit if already finalized
		if (auction.finalized) return;

		// Distribute bids
		_distributeUSD(auction.sum);

		// Send emissions to treasury
		if (auction.treasuryEmission > 0) {
			GO.safeTransfer(treasury, auction.treasuryEmission);
		}

		// Mark Finalized
		auction.finalized = true;
		emit AuctionFinalized(auction.lot);
	}

	function claimEmissions(Auction storage auction) internal {
		AuctionUser storage user = auctionUsers[auction.lot][msg.sender];

		// Exit if user already claimed emissions from auction
		if (user.claimed) return;

		// Exit early if nothing to claim
		if (user.bids == 0) return;

		// Calculate and distribute emissions
		uint256 emissions = (auction.biddersEmission * (user.bids * 1e18)) / auction.bids;
		GO.safeTransfer(msg.sender, emissions);

		// Mark claimed
		user.claimed = true;
		emit UserClaimedLotEmissions(auction.lot, msg.sender, emissions);
	}

	///////////////////
	// USER
	///////////////////

	// NAME

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

	// GAS SAVINGS

	function addBalance(uint256 _amount) public nonReentrant {
		if (_amount > GO.balanceOf(msg.sender)) revert BadDeposit();

		USD.safeTransferFrom(msg.sender, address(this), _amount);
		userBalance[msg.sender] += _amount;

		emit AddedBalance(msg.sender, _amount);
	}
	function withdrawBalance(uint256 _amount) public nonReentrant {
		if (_amount > userBalance[msg.sender]) revert BadWithdrawal();

		USD.safeTransferFrom(address(this), msg.sender, _amount);
		userBalance[msg.sender] -= _amount;

		emit WithdrewBalance(msg.sender, _amount);
	}

	///////////////////
	// VIEW
	///////////////////

	function getBidsData(
		address _user,
		uint256 _lot
	) public view validAuctionLot(_lot) returns (uint256 userBids, uint256 auctionBids) {
		userBids = auctionUsers[_lot][_user].bids;
		auctionBids = auctions[_lot].bids;
	}
	function getAuction(uint256 _lot) public view validAuctionLot(_lot) returns (Auction memory) {
		return auctions[_lot];
	}
	function getAuctionTokenEarned(address _user, uint256 _lot) public view validAuctionLot(_lot) returns (uint256) {
		// Prevent div by 0
		if (auctionUsers[_lot][_user].bids == 0 || auctions[_lot].bids == 0) return 0;

		return (auctionUsers[_lot][_user].bids * auctions[_lot].biddersEmission) / auctions[_lot].bids;
	}
	function getCurrentEpochData()
		public
		view
		returns (
			uint256 epoch,
			uint256 start,
			uint256 end,
			uint256 daysRemaining,
			uint256 emissionsRemaining,
			uint256 dailyEmission
		)
	{
		return _getEpochDataAtTimestamp(block.timestamp);
	}
}