// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "./IAuctioneer.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IWETH } from "./WETH9.sol";
import { IAuctioneerFarm } from "./IAuctioneerFarm.sol";

// Dont need everything from most math libs, and nearing contract size limit
library GBMath {
	function transformDec(uint256 amount, uint8 from, uint8 to) internal pure returns (uint256) {
		return (amount * 10 ** to) / 10 ** from;
	}
	function min(uint256 a, uint256 b) internal pure returns (uint256) {
		return a < b ? a : b;
	}
	function max(uint256 a, uint256 b) internal pure returns (uint256) {
		return a > b ? a : b;
	}
	function scaleByBP(uint256 amount, uint256 bp) internal pure returns (uint256) {
		if (bp == 10000) return amount;
		return (amount * bp) / 10000;
	}
}

library AuctionViewUtils {
	function hasRunes(Auction storage auction) public view returns (bool) {
		return auction.runes.length > 0;
	}

	function activeWindow(Auction storage auction) public view returns (uint256) {
		// Before auction opens, active window is 0
		// This case gets caught by first window

		// Check if timestamp is before the end of each window, if it is, return that windows index
		for (uint256 i = 0; i < auction.windows.length; i++) {
			if (block.timestamp < auction.windows[i].windowCloseTimestamp) return i;
		}

		// Shouldn't ever get here, maybe in 10 years or so.
		return auction.windows.length - 1;
	}

	// Recursive fetcher of next bid cutoff timestamp
	// Open window or negative window will look to next window
	// Timed or infinite window will give timestamp to exit
	function getWindowNextBidBy(Auction storage auction, uint256 window) public view returns (uint256) {
		if (auction.windows[window].windowType == BidWindowType.OPEN) return getWindowNextBidBy(auction, window + 1);

		// Timed or infinite window
		// max(last bid timestamp, window open timestamp) + window timer
		// A bid 5 seconds before window closes will be given the timer of the current window, even if it overflows into next window
		return
			GBMath.max(auction.bidData.bidTimestamp, auction.windows[window].windowOpenTimestamp) +
			auction.windows[window].timer;
	}

	function getNextBidBy(Auction storage auction) public view returns (uint256) {
		return getWindowNextBidBy(auction, activeWindow(auction));
	}

	function isBiddingOpen(Auction storage auction) public view returns (bool) {
		// Early escape if the auction has been finalized
		if (auction.finalized) return false;

		// Early escape if auction not yet unlocked
		if (block.timestamp < auction.unlockTimestamp) return false;

		// Closed if nextBidBy is in future
		return block.timestamp <= auction.bidData.nextBidBy;
	}
	function validateBiddingOpen(Auction storage auction) public view {
		if (!isBiddingOpen(auction)) revert BiddingClosed();
	}

	function isEnded(Auction storage auction) public view returns (bool) {
		// Early escape if the auction has been finalized
		if (auction.finalized) return true;

		// Early escape if auction not yet unlocked
		if (block.timestamp < auction.unlockTimestamp) return false;

		// Closed if nextBidBy is in past
		return block.timestamp > auction.bidData.nextBidBy;
	}
	function validateEnded(Auction storage auction) public view {
		if (!isEnded(auction)) revert AuctionStillRunning();
	}
}

library AuctionMutateUtils {
	using GBMath for uint256;
	using SafeERC20 for IERC20;

	function addBidWindows(Auction storage auction, AuctionParams memory _params, uint256 _bonusTime) internal {
		uint256 openTimestamp = _params.unlockTimestamp;
		for (uint8 i = 0; i < _params.windows.length; i++) {
			uint256 closeTimestamp = openTimestamp + _params.windows[i].duration;
			if (_params.windows[i].windowType == BidWindowType.INFINITE) {
				closeTimestamp = openTimestamp + 315600000; // 10 years, hah
			}
			uint256 timer = _params.windows[i].windowType == BidWindowType.OPEN ? 0 : _params.windows[i].timer + _bonusTime;
			auction.windows.push(
				BidWindow({
					windowType: _params.windows[i].windowType,
					windowOpenTimestamp: openTimestamp,
					windowCloseTimestamp: closeTimestamp,
					timer: timer
				})
			);
			openTimestamp += _params.windows[i].duration;
		}
	}

	function addRewards(Auction storage auction, AuctionParams memory params) internal {
		auction.rewards.estimatedValue = params.lotValue;

		for (uint8 i = 0; i < params.tokens.length; i++) {
			auction.rewards.tokens.push(params.tokens[i]);
		}

		for (uint8 i = 0; i < params.nfts.length; i++) {
			auction.rewards.nfts.push(params.nfts[i]);
		}
	}

	function addRunes(Auction storage auction, AuctionParams memory params) internal {
		if (params.runeSymbols.length == 0) return;

		// Add empty rune (cannot be bid on), to offset array indices
		auction.runes.push(BidRune({ runeSymbol: 0, bids: 0, users: 0 }));

		for (uint8 i = 0; i < params.runeSymbols.length; i++) {
			auction.runes.push(BidRune({ runeSymbol: params.runeSymbols[i], bids: 0, users: 0 }));
		}
	}

	function _transferLotTokenTo(
		TokenData memory token,
		address to,
		uint256 userShareOfLot,
		bool unwrapETH,
		address ETH,
		address WETH
	) internal {
		if (token.token == ETH) {
			if (unwrapETH) {
				// If lot token is ETH, it is held in contract as WETH, and needs to be unwrapped before being sent to user
				IWETH(WETH).withdraw((token.amount * userShareOfLot) / 1e18);
				(bool sent, ) = to.call{ value: (token.amount * userShareOfLot) / 1e18 }("");
				if (!sent) revert ETHTransferFailed();
			} else {
				IERC20(address(WETH)).safeTransfer(to, (token.amount * userShareOfLot) / 1e18);
			}
		} else {
			// Transfer as default ERC20
			IERC20(token.token).safeTransfer(to, (token.amount * userShareOfLot) / 1e18);
		}
	}

	function transferLotTo(
		Auction storage auction,
		address to,
		uint256 userShareOfLot,
		bool unwrapETH,
		address ETH,
		address WETH
	) internal {
		// Return lot tokens
		for (uint8 i = 0; i < auction.rewards.tokens.length; i++) {
			_transferLotTokenTo(auction.rewards.tokens[i], to, userShareOfLot, unwrapETH, ETH, WETH);
		}

		// Transfer lot nfts
		for (uint8 i = 0; i < auction.rewards.nfts.length; i++) {
			IERC721(auction.rewards.nfts[i].nft).transferFrom(address(this), to, auction.rewards.nfts[i].id);
		}
	}

	function transferLotFrom(Auction storage auction, address from, address ETH, address WETH) internal {
		// Transfer tokens from
		for (uint8 i = 0; i < auction.rewards.tokens.length; i++) {
			address token = auction.rewards.tokens[i].token == ETH ? WETH : auction.rewards.tokens[i].token;
			IERC20(token).safeTransferFrom(from, address(this), auction.rewards.tokens[i].amount);
		}
		// Transfer nfts from
		for (uint8 i = 0; i < auction.rewards.nfts.length; i++) {
			IERC721(auction.rewards.nfts[i].nft).safeTransferFrom(from, address(this), auction.rewards.nfts[i].id);
		}
	}

	function distributeLotProfit(
		Auction storage,
		IERC20 USD,
		uint256 amount,
		address treasury,
		address farm,
		uint256 treasurySplit
	) internal returns (uint256 farmDistribution) {
		// Calculate distributions
		uint256 treasuryDistribution = amount.scaleByBP(treasurySplit);
		farmDistribution = amount - treasuryDistribution;

		// Add unused farm distribution to treasury (if no farm set, send all funds to treasury)
		if (farm == address(0)) {
			treasuryDistribution += farmDistribution;
			farmDistribution = 0;
		}

		// If farm not set, farm distribution will be 0
		// If farm has 0 staked, fallback to treasury
		if (farmDistribution > 0) {
			USD.approve(farm, farmDistribution);
			bool received = IAuctioneerFarm(farm).receiveUsdDistribution(farmDistribution);
			if (!received) {
				treasuryDistribution += farmDistribution;
				USD.approve(farm, 0);
			}
		}

		// Distribute
		if (treasuryDistribution > 0) {
			USD.safeTransfer(treasury, treasuryDistribution);
		}
	}

	function distributeLotRevenue(
		Auction storage auction,
		IERC20 USD,
		address treasury,
		address farm,
		uint256 treasurySplit
	) internal {
		uint256 lotValue = auction.rewards.estimatedValue.transformDec(18, auction.bidData.usdDecimals);
		uint256 reimbursement = auction.bidData.revenue;
		uint256 profit = 0;

		// Reduce treasury amount received if revenue outstripped lot value
		if (auction.bidData.revenue > lotValue.scaleByBP(11000)) {
			reimbursement = lotValue.scaleByBP(11000);
			profit = auction.bidData.revenue - reimbursement;
		}

		USD.safeTransfer(treasury, reimbursement);

		if (profit > 0) {
			distributeLotProfit(auction, USD, profit, treasury, farm, treasurySplit);
		}
	}
}

library AuctionParamsUtils {
	function validateUnlock(AuctionParams memory _params) public view {
		if (_params.unlockTimestamp < block.timestamp) revert UnlockAlreadyPassed();
	}

	function validateTokens(AuctionParams memory _params) public pure {
		if (_params.tokens.length > 4) revert TooManyTokens();
	}

	function validateNFTs(AuctionParams memory _params) public pure {
		if (_params.nfts.length > 4) revert TooManyNFTs();
		if (_params.nfts.length > 0 && _params.runeSymbols.length > 0) revert CannotHaveNFTsWithRunes();
	}

	function validateAnyReward(AuctionParams memory _params) public pure {
		if (_params.nfts.length == 0 && _params.tokens.length == 0) revert NoRewards();
	}

	// YES I KNOW that this is inefficient, this is an owner facing function.
	// Legibility and clarity > once daily gas price.
	function validateBidWindows(AuctionParams memory _params) public pure {
		// VALIDATE: Acceptable number of bidding windows
		if (_params.windows.length == 0 || _params.windows.length > 4) revert InvalidBidWindowCount();

		// VALIDATE: Windows must flow from open -> timed -> infinite
		BidWindowType runningType = BidWindowType.OPEN;
		for (uint8 i = 0; i < _params.windows.length; i++) {
			if (_params.windows[i].windowType < runningType) revert InvalidWindowOrder();
			runningType = _params.windows[i].windowType;
		}

		// VALIDATE: Last window must be infinite window
		if (_params.windows[_params.windows.length - 1].windowType != BidWindowType.INFINITE)
			revert LastWindowNotInfinite();

		// VALIDATE: Only one infinite window can exist
		uint8 infCount = 0;
		for (uint8 i = 0; i < _params.windows.length; i++) {
			if (_params.windows[i].windowType == BidWindowType.INFINITE) infCount += 1;
		}
		if (infCount > 1) revert MultipleInfiniteWindows();

		// VALIDATE: Windows must have a valid duration (if not infinite)
		for (uint8 i = 0; i < _params.windows.length; i++) {
			if (_params.windows[i].windowType != BidWindowType.INFINITE && _params.windows[i].duration < 1 hours)
				revert WindowTooShort();
		}

		// VALIDATE: Timed windows must have a valid timer
		for (uint8 i = 0; i < _params.windows.length; i++) {
			// TIMED and INFINITE windows should have a timer >= 60 seconds
			if (_params.windows[i].windowType != BidWindowType.OPEN && _params.windows[i].timer < 30 seconds)
				revert InvalidBidWindowTimer();

			// OPEN windows should have a timer of 0 (no timer)
			if (_params.windows[i].windowType == BidWindowType.OPEN && _params.windows[i].timer != 0)
				revert InvalidBidWindowTimer();
		}
	}

	function validateRunes(AuctionParams memory _params) public pure {
		// Early escape if no runes
		if (_params.runeSymbols.length == 0) return;

		// VALIDATE: Number of runes
		if (_params.runeSymbols.length == 1 || _params.runeSymbols.length > 5) revert InvalidRunesCount();

		// VALIDATE: Rune symbols > 0 (account for empty rune at index 0)
		for (uint8 i = 0; i < _params.runeSymbols.length; i++) {
			if (_params.runeSymbols[i] == 0) revert InvalidRuneSymbol();
		}

		// VALIDATE: No duplicate symbols
		// Example:
		// Symbols = [0, 1, 2, 2]
		// i = 0 - 2
		// 	i = 0 :: j = 1 - 3
		// 	i = 1 :: j = 2 - 3
		//  i = 2 :: j = 3
		// checks: s[0]:s[1] ✔, s[0]:s[2] ✔, s[0]:s[3] ✔, s[1]:s[2] ✔, s[1]:s[3] ✔, s[2]:s[3] ✘
		for (uint8 i = 0; i < _params.runeSymbols.length - 1; i++) {
			for (uint8 j = i + 1; j < _params.runeSymbols.length; j++) {
				if (_params.runeSymbols[i] == _params.runeSymbols[j]) revert DuplicateRuneSymbols();
			}
		}
	}

	// Wholistic validation
	function validate(AuctionParams memory _params) public view {
		validateUnlock(_params);
		validateTokens(_params);
		validateNFTs(_params);
		validateAnyReward(_params);
		validateBidWindows(_params);
		validateRunes(_params);
	}
}
