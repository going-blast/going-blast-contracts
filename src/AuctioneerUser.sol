// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { Auctioneer } from "./Auctioneer.sol";
import "./IAuctioneer.sol";
import { GBMath } from "./AuctionUtils.sol";
import { AuctioneerEmissions } from "./AuctioneerEmissions.sol";

interface IAuctioneerUser {
	function link(address _auctioneerEmissions) external;
	function bid(
		uint256 _lot,
		address _user,
		uint256 _bidAmount,
		uint256 _biddersEmission,
		BidOptions memory _options
	) external returns (bool isUsersFirstBid);
	function preselectRune(uint256 _lot, address _user, uint8 _rune) external;
	function claimLot(uint256 _lot, address _user) external returns (uint8 rune, uint256 bids);
	function harvestAuctionEmissions(
		uint256 _lot,
		address _user,
		uint256 _unlockTimestamp,
		uint256 _auctionBids,
		uint256 _biddersEmission
	) external;
	function payFromFunds(address _user, uint256 _amount) external;
}

contract AuctioneerUser is IAuctioneerUser, Ownable, ReentrancyGuard, AuctioneerEvents {
	using GBMath for uint256;
	using SafeERC20 for IERC20;
	using EnumerableSet for EnumerableSet.UintSet;

	IAuctioneer public auctioneer;
	AuctioneerEmissions public auctioneerEmissions;
	bool public linked;

	// AUCTION USER
	mapping(uint256 => mapping(address => AuctionUser)) public auctionUsers;
	mapping(address => EnumerableSet.UintSet) internal userInteractedLots;
	mapping(address => EnumerableSet.UintSet) internal userUnharvestedLots;
	mapping(address => string) public userAlias;
	mapping(string => address) public aliasUser;

	// USER FUNDS
	IERC20 public USD;
	mapping(address => uint256) public userFunds;

	constructor(IERC20 _usd) Ownable(msg.sender) {
		USD = _usd;
	}

	function link(address _auctioneerEmissions) public {
		if (linked) revert AlreadyLinked();
		linked = true;

		auctioneer = IAuctioneer(payable(msg.sender));
		auctioneerEmissions = AuctioneerEmissions(_auctioneerEmissions);
	}

	///////////////////
	// MODIFIERS
	///////////////////

	modifier onlyAuctioneer() {
		if (msg.sender != address(auctioneer)) revert NotAuctioneer();
		_;
	}

	modifier validUserRuneSelection(
		uint256 _lot,
		address _user,
		uint8 _rune
	) {
		if (auctionUsers[_lot][_user].rune != 0 && auctionUsers[_lot][_user].rune != _rune) revert CantSwitchRune();
		_;
	}

	///////////////////
	// BID
	///////////////////

	function bid(
		uint256 _lot,
		address _user,
		uint256 _bidAmount,
		uint256 _biddersEmission,
		BidOptions memory _options
	) public onlyAuctioneer validUserRuneSelection(_lot, _user, _options.rune) returns (bool isUsersFirstBid) {
		AuctionUser storage user = auctionUsers[_lot][_user];
		isUsersFirstBid = user.bids == 0;

		// Force bid count to be at least one
		if (_options.multibid == 0) _options.multibid = 1;

		// Mark users bids
		user.bids += _options.multibid;

		// Mark users rune
		if (user.rune != _options.rune) {
			user.rune = _options.rune;
		}

		// Mark user has interacted with this lot
		userInteractedLots[_user].add(_lot);

		// Mark whether user will have emissions (any bid guarantees emissions)
		if (_biddersEmission > 0) {
			userUnharvestedLots[_user].add(_lot);
		}

		emit Bid(_lot, _user, _bidAmount, userAlias[_user], _options);
	}

	function preselectRune(
		uint256 _lot,
		address _user,
		uint8 _rune
	) public onlyAuctioneer validUserRuneSelection(_lot, _user, _rune) {
		AuctionUser storage user = auctionUsers[_lot][_user];
		user.rune = _rune;
		emit PreselectedRune(_lot, _user, _rune);
	}

	///////////////////
	// CLAIM
	///////////////////

	function claimLot(uint256 _lot, address _user) public onlyAuctioneer returns (uint8 rune, uint256 bids) {
		AuctionUser storage user = auctionUsers[_lot][_user];

		// Winner has already paid for and claimed the lot (or their share of it)
		if (user.lotClaimed) revert UserAlreadyClaimedLot();

		// Mark lot as claimed
		user.lotClaimed = true;

		// Return values
		rune = user.rune;
		bids = user.bids;
	}

	///////////////////
	// HARVEST
	///////////////////

	function harvestAuctionEmissions(
		uint256 _lot,
		address _user,
		uint256 _unlockTimestamp,
		uint256 _auctionBids,
		uint256 _biddersEmission
	) public onlyAuctioneer {
		AuctionUser storage user = auctionUsers[_lot][_user];

		// Exit if user already harvested emissions from auction
		if (user.emissionsHarvested) return;

		// Exit early if nothing to claim
		if (user.bids == 0) return;

		// Mark harvested
		user.emissionsHarvested = true;
		userUnharvestedLots[_user].remove(_lot);

		// Signal auctioneerEmissions to harvest user's emissions
		(user.harvestedEmissions, user.burnedEmissions) = auctioneerEmissions.harvestEmissions(
			_user,
			(_biddersEmission * user.bids) / _auctionBids,
			_unlockTimestamp
		);

		emit UserHarvestedLotEmissions(_lot, _user, user.harvestedEmissions, user.burnedEmissions);
	}

	///////////////////
	// FUNDS
	///////////////////

	function payFromFunds(address _user, uint256 _amount) public onlyAuctioneer {
		if (_amount > userFunds[_user]) revert InsufficientFunds();
		userFunds[_user] -= _amount;
	}

	function addFundsWithPermit(uint256 _amount, PermitData memory _permitData) public nonReentrant {
		IERC20Permit(_permitData.token).permit(
			msg.sender,
			address(this),
			_permitData.value,
			_permitData.deadline,
			_permitData.v,
			_permitData.r,
			_permitData.s
		);
		_addFunds(_amount);
	}
	function addFunds(uint256 _amount) public nonReentrant {
		_addFunds(_amount);
	}
	function _addFunds(uint256 _amount) internal {
		if (_amount > USD.balanceOf(msg.sender)) revert BadDeposit();

		USD.safeTransferFrom(msg.sender, address(auctioneer), _amount);
		userFunds[msg.sender] += _amount;

		emit AddedFunds(msg.sender, _amount);
	}

	function withdrawFunds(uint256 _amount) public nonReentrant {
		if (_amount > userFunds[msg.sender]) revert BadWithdrawal();

		// Ensure that only the users funds can be withdrawn
		auctioneer.approveWithdrawUserFunds(_amount);

		USD.safeTransferFrom(address(auctioneer), msg.sender, _amount);
		userFunds[msg.sender] -= _amount;

		emit WithdrewFunds(msg.sender, _amount);
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

	///////////////////
	// VIEW
	///////////////////

	function getAuctionUser(uint256 _lot, address _user) public view returns (AuctionUser memory) {
		return auctionUsers[_lot][_user];
	}

	function getUserInteractedLots(address _user) public view returns (uint256[] memory) {
		return userInteractedLots[_user].values();
	}

	function getUserUnharvestedLots(address _user) public view returns (uint256[] memory) {
		return userUnharvestedLots[_user].values();
	}

	function getUserLotInfo(uint256 _lot, address _user) public view returns (UserLotInfo memory info) {
		Auction memory auction = auctioneer.getAuction(_lot);
		AuctionUser memory user = auctionUsers[_lot][_user];

		info.lot = auction.lot;
		info.rune = user.rune;

		// Bids
		info.bidCounts.user = user.bids;
		info.bidCounts.rune = auction.runes.length == 0 || user.rune == 0 ? 0 : auction.runes[user.rune].bids;
		info.bidCounts.auction = auction.bidData.bids;

		// Emissions
		info.matureTimestamp = (auction.day * 1 days) + auctioneerEmissions.emissionTaxDuration();
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
}
