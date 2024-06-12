// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

enum BidWindowType {
	OPEN,
	TIMED,
	INFINITE
}
enum PaymentType {
	WALLET,
	VOUCHER
}

// Params

struct BidRune {
	uint8 runeSymbol;
	uint256 bids;
}

struct PermitData {
	address token;
	uint256 value;
	uint256 deadline;
	uint8 v;
	bytes32 r;
	bytes32 s;
}

// Alphabetical field ordering for json parsing
struct BidWindowParams {
	uint256 duration;
	uint256 timer;
	BidWindowType windowType;
}

// Alphabetical field ordering for json parsing
struct TokenData {
	uint256 amount;
	address token;
}

// Alphabetical field ordering for json parsing
struct NftData {
	uint256 id;
	address nft;
}

// Alphabetical field ordering for json parsing
struct AuctionParams {
	string name;
	NftData[] nfts;
	uint8[] runeSymbols;
	TokenData[] tokens;
	uint256 unlockTimestamp;
	BidWindowParams[] windows;
	uint256 bidCost;
	uint256 bidIncrement;
	uint256 startingBid;
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
struct AuctionBidData {
	uint256 revenue;
	uint256 bid;
	uint256 bidTimestamp;
	uint256 nextBidBy;
	address bidUser;
	uint8 bidRune;
	uint256 bids; // number of bids during auction
	uint256 bidCost; // Frozen value to prevent updating bidCost from messing with revenue calculations
	uint256 bidIncrement;
}

struct Auction {
	address creator;
	uint256 lot;
	uint256 day;
	string name;
	uint256 unlockTimestamp;
	BidRune[] runes;
	BidWindow[] windows;
	AuctionLot rewards;
	AuctionBidData bidData;
	uint256 treasuryCut;
	bool finalized;
	uint256 initialBlock;
}

struct AuctionUser {
	uint256 bids;
	uint8 rune; // indexed starting at 1 to check if rune has been set (defaults to 0)
	bool lotClaimed;
}

// Returns
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
	// Winning bid
	bool isWinner;
	bool lotClaimed;
	uint256 shareOfLot;
	uint256 price;
}
struct AuctionExt {
	uint256 lot;
	uint256 blockTimestamp;
	bool isBiddingOpen;
	bool isEnded;
	uint256 activeWindow;
}

struct DailyAuctions {
	uint256 day;
	uint256[] lots;
}

error NotAuctioneer();
error NotAuctioneerAuction();
error AlreadyInitialized();
error TreasuryNotSet();
error TeamTreasuryNotSet();
error TooManyAuctionsPerDay();
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
error NotEnoughETHToCoverLots();
error AuctionEnded();
error AuctionNotYetOpen();
error AuctionStillRunning();
error NoRewards();
error AuctionClosed();
error NotCancellable();
error TooSteep();
error ZeroAddress();
error AlreadyLinked();
error UnlockAlreadyPassed();
error BadDeposit();
error BadWithdrawal();
error InvalidAlias();
error AliasTaken();
error ETHTransferFailed();
error MustBidAtLeastOnce();
error NotWinner();
error UserAlreadyClaimedLot();
error InvalidBidCount();
error InvalidRune();
error InvalidRuneSymbol();
error InvalidRunesCount();
error DuplicateRuneSymbols();
error CantSwitchRune();
error CannotHaveNFTsWithRunes();
error IncorrectETHPaymentAmount();
error SentETHButNotWalletPayment();
error Muted();

error Unauthorized();

interface AuctioneerEvents {
	// ADMIN
	event Linked(address indexed _auctioneer, address _auctioneerAuction);
	event Initialized();
	event MutedUser(address indexed _user, bool _muted);

	// CONSTS
	event UpdatedStartingBid(uint256 _startingBid);
	event UpdatedBidCost(uint256 _bidCost);
	event UpdatedBidIncrement(uint256 _bidIncrement);
	event UpdatedTreasuryCut(uint256 _treasuryCut);
	event UpdatedRuneSwitchPenalty(uint256 _penalty);
	event UpdatedTreasury(address indexed _treasury);
	event UpdatedTeamTreasury(address indexed _teamTreasury);
	event UpdatedTeamTreasurySplit(uint256 _split);
	event UpdatedAlias(address indexed _user, string _alias);
	event UpdatedRunicLastBidderBonus(uint256 _bonus);
	event UpdatedCreateAuctionRequiresRole(bool _required);

	// AUCTION STATE
	event AuctionCreated(address indexed _creator, uint256 indexed _lot);
	event AuctionCancelled(address indexed _creator, uint256 indexed _lot);
	event AuctionFinalized(uint256 indexed _lot);

	// USER INTERACTIONS
	event Bid(
		uint256 indexed _lot,
		address indexed _user,
		string _message,
		string _alias,
		uint8 _rune,
		uint8 _prevRune,
		uint256 _bid,
		uint256 _bidCount,
		uint256 _timestamp
	);
	event SelectedRune(
		uint256 indexed _lot,
		address indexed _user,
		string _message,
		string _alias,
		uint8 _rune,
		uint8 _prevRune
	);
	event Messaged(uint256 indexed _lot, address indexed _user, string _message, string _alias, uint8 _rune);
	event Claimed(uint256 indexed _lot, address indexed _user, string _message, string _alias, uint8 _rune);

	// MIGRATION
	event MigrationQueued(address indexed _migrator, address indexed _dest);
	event MigrationCancelled(address indexed _migrator, address indexed _dest);
	event MigrationExecuted(address indexed _migrator, address indexed _dest, uint256 _unallocated);
}
