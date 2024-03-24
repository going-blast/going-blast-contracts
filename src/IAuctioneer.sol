// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

enum BidWindowType {
	OPEN,
	TIMED,
	INFINITE
}
enum BidPaymentType {
	WALLET,
	FUNDS,
	VOUCHER
}
enum LotPaymentType {
	WALLET,
	FUNDS
}

// Params

struct BidRune {
	uint8 runeSymbol;
	uint256 bids;
	uint256 users;
}

struct BidOptions {
	BidPaymentType paymentType;
	uint256 multibid;
	string message;
	uint8 rune;
}
struct ClaimLotOptions {
	LotPaymentType paymentType;
	bool unwrapETH;
}

struct BidWindowParams {
	BidWindowType windowType;
	uint256 duration;
	uint256 timer;
}

struct TokenData {
	address token;
	uint256 amount;
}

struct NftData {
	address nft;
	uint256 id;
}

struct AuctionParams {
	bool isPrivate;
	uint256 emissionBP; // Emission of this auction of the day's emission (usually 100%)
	string name;
	uint8[] runeSymbols;
	TokenData[] tokens;
	NftData[] nfts;
	BidWindowParams[] windows;
	uint256 unlockTimestamp;
	uint256 lotValue;
}

// Storage

struct BidWindow {
	BidWindowType windowType;
	uint256 windowOpenTimestamp;
	uint256 windowCloseTimestamp; // 0 for window that goes forever
	uint256 timer; // 0 for no timer, >60 for other timers (1m / 2m / 5m)
}

struct AuctionLot {
	uint256 estimatedValue; // Estimated value of the lot (1 ETH = 4000 USD)
	TokenData[] tokens;
	NftData[] nfts;
}
struct AuctionEmissions {
	uint256 bp; // Scaler of emissions this auction, needed to reduce bp if auction cancelled
	uint256 biddersEmission; // token to be distributed through auction to bidders
	uint256 treasuryEmission; // token to be distributed to treasury at end of auction (10% of total emission)
}
struct AuctionBidData {
	uint256 revenue;
	uint256 bid;
	uint256 bidTimestamp;
	uint256 nextBidBy;
	address bidUser;
	uint8 bidRune;
	uint256 bids; // number of bids during auction
	uint256 bidCost; // Frozen value to prevent updating bidCost from messing with revenue calculations
	uint8 usdDecimals;
}

struct Auction {
	uint256 lot;
	uint256 day;
	string name;
	bool isPrivate; // whether the auction requires wallet / staked Gavel
	uint256 unlockTimestamp;
	BidRune[] runes;
	BidWindow[] windows;
	AuctionEmissions emissions;
	AuctionLot rewards;
	AuctionBidData bidData;
	bool finalized;
}

struct AuctionUser {
	uint256 bids;
	uint8 rune; // indexed starting at 1 to check if rune has been set (defaults to 0)
	bool lotClaimed;
	bool emissionsHarvested;
	uint256 harvestedEmissions;
	uint256 burnedEmissions;
}

// Returns
struct EpochData {
	uint256 epoch;
	uint256 start;
	uint256 end;
	uint256 daysRemaining;
	uint256 emissionsRemaining;
	uint256 dailyEmission;
}
struct BidCounts {
	uint256 user;
	uint256 rune;
	uint256 auction;
}
struct UserLotInfo {
	uint256 lot;
	uint8 rune;
	// Bids
	BidCounts bidCounts;
	// Emissions
	uint256 matureTimestamp;
	uint256 timeUntilMature;
	uint256 emissionsEarned;
	bool emissionsHarvested;
	uint256 harvestedEmissions;
	uint256 burnedEmissions;
	// Winning bid
	bool isWinner;
	bool lotClaimed;
}

error NotAuctioneer();
error NotAuctioneerUser();
error GONotYetReceived();
error EmissionsNotInitialized();
error AlreadyInitialized();
error TreasuryNotSet();
error TooManyAuctionsPerDay();
error InvalidDailyEmissionBP();
error Invalid();
error InvalidAuctionLot();
error InvalidWindowOrder();
error WindowTooShort();
error InvalidBidWindowCount();
error InvalidBidWindowTimer();
error LastWindowNotInfinite();
error MultipleInfiniteWindows();
error TooManyTokens();
error TooManyNFTs();
error BiddingClosed();
error AuctionStillRunning();
error NoRewards();
error AuctionClosed();
error NotCancellable();
error TooSteep();
error ZeroAddress();
error AlreadyLinked();
error PrivateAuction();
error UnlockAlreadyPassed();
error BadDeposit();
error BadWithdrawal();
error InsufficientFunds();
error InvalidAlias();
error AliasTaken();
error ETHTransferFailed();
error MustBidAtLeastOnce();
error NotWinner();
error UserAlreadyClaimedLot();
error InvalidRune();
error InvalidRuneSymbol();
error InvalidRunesCount();
error DuplicateRuneSymbols();
error CantSwitchRune();
error CannotHaveNFTsWithRunes();

interface AuctioneerEvents {
	event Linked(address indexed _auctioneer, address indexed _auctioneerUser, address indexed _auctioneerEmissions);
	event Initialized();
	event InitializedEmissions();
	event UpdatedStartingBid(uint256 _startingBid);
	event UpdatedBidCost(uint256 _bidCost);
	event UpdatedEarlyHarvestTax(uint256 _earlyHarvestTax);
	event UpdatedEmissionTaxDuration(uint256 _emissionTax);
	event AuctionCreated(uint256 indexed _lot);
	event Bid(uint256 indexed _lot, address indexed _user, uint256 _bid, string _alias, BidOptions _options);
	event AuctionFinalized(uint256 indexed _lot);
	event UserClaimedLot(
		uint256 indexed _lot,
		address indexed _user,
		uint8 _rune,
		uint256 _userShareOfLot,
		TokenData[] _tokens,
		NftData[] _nfts
	);
	event UserHarvestedLotEmissions(uint256 _lot, address indexed _user, uint256 _userEmissions, uint256 _burnEmissions);
	event AuctionCancelled(uint256 indexed _lot);
	event UpdatedTreasury(address indexed _treasury);
	event UpdatedFarm(address indexed _farm);
	event UpdatedTreasurySplit(uint256 _split);
	event UpdatedPrivateAuctionRequirement(uint256 _requirement);
	event InitializedAuctions();
	event AddedFunds(address _user, uint256 _amount);
	event WithdrewFunds(address _user, uint256 _amount);
	event UpdatedAlias(address _user, string _alias);
}

interface IAuctioneer {
	function getAuction(uint256 _lot) external view returns (Auction memory);
	function approveWithdrawUserFunds(uint256 _amount) external;
}
