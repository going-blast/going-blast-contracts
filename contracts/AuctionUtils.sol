// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4;

import "./IAuctioneer.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IWETH } from "./WETH9.sol";

library AuctionUtils {
	using SafeERC20 for IERC20;

	function min(uint256 a, uint256 b) internal pure returns (uint256) {
		return a < b ? a : b;
	}
	function max(uint256 a, uint256 b) internal pure returns (uint256) {
		return a > b ? a : b;
	}

	function finalize(Auction storage auction) internal {
		auction.finalized = true;
	}

	function activeWindow(Auction storage auction) internal view returns (uint256) {
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
	function getWindowNextBidBy(Auction storage auction, uint256 window) internal view returns (uint256) {
		if (auction.windows[window].windowType == BidWindowType.OPEN) return getWindowNextBidBy(auction, window + 1);

		// Timed or infinite window
		// max(last bid timestamp, window open timestamp) + window timer
		// A bid 5 seconds before window closes will be given the timer of the current window, even if it overflows into next window
		return
			max(auction.bidData.bidTimestamp, auction.windows[window].windowOpenTimestamp) + auction.windows[window].timer;
	}

	function getNextBidBy(Auction storage auction) internal view returns (uint256) {
		return getWindowNextBidBy(auction, activeWindow(auction));
	}

	function isBiddingOpen(Auction storage auction) internal view returns (bool) {
		// Early escape if the auction has been finalized
		if (auction.finalized) return false;

		// Early escape if auction not yet unlocked
		if (block.timestamp < auction.unlockTimestamp) return false;

		// Closed if nextBidBy is in future
		return block.timestamp <= auction.bidData.nextBidBy;
	}
	function validateBiddingOpen(Auction storage auction) internal view {
		if (!isBiddingOpen(auction)) revert BiddingClosed();
	}

	function isEnded(Auction storage auction) internal view returns (bool) {
		// Early escape if the auction has been finalized
		if (auction.finalized) return true;

		// Early escape if auction not yet unlocked
		if (block.timestamp < auction.unlockTimestamp) return false;

		// Closed if nextBidBy is in past
		return block.timestamp > auction.bidData.nextBidBy;
	}
	function validateEnded(Auction storage auction) internal view {
		if (!isEnded(auction)) revert AuctionStillRunning();
	}

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

	// Rewards
	function _transferLotToken(
		address _token,
		address _to,
		uint256 _amount,
		bool _unwrapETH,
		address ETH,
		address WETH
	) internal {
		if (_token == ETH) {
			if (_unwrapETH) {
				// If lot token is ETH, it is held in contract as WETH, and needs to be unwrapped before being sent to user
				IWETH(WETH).withdraw(_amount);
				(bool sent, ) = _to.call{ value: _amount }("");
				if (!sent) revert ETHTransferFailed();
			} else {
				IERC20(address(WETH)).safeTransfer(_to, _amount);
			}
		} else {
			// Transfer as default ERC20
			IERC20(_token).safeTransfer(_to, _amount);
		}
	}

	function transferLot(Auction storage auction, address to, bool _unwrapETH, address ETH, address WETH) internal {
		// Return lot to treasury
		for (uint8 i = 0; i < auction.rewards.tokens.length; i++) {
			_transferLotToken(auction.rewards.tokens[i], to, auction.rewards.amounts[i], _unwrapETH, ETH, WETH);
		}

		// Transfer lot nfts to treasury
		for (uint8 i = 0; i < auction.rewards.nfts.length; i++) {
			IERC721(auction.rewards.nfts[i]).transferFrom(msg.sender, to, auction.rewards.nftIds[i]);
		}
	}
}

library AuctionParamsUtils {
	function validateUnlock(AuctionParams memory _params) internal view {
		if (_params.unlockTimestamp < block.timestamp) revert UnlockAlreadyPassed();
	}

	function validateTokens(AuctionParams memory _params) internal pure {
		if (_params.tokens.length > 4) revert TooManyTokens();
		if (_params.tokens.length != _params.amounts.length) revert LengthMismatch();
		if (_params.tokens.length == 0) revert NoTokens();
	}

	function validateNFTs(AuctionParams memory _params) internal pure {
		if (_params.nfts.length > 4) revert TooManyTokens();
		if (_params.nfts.length != _params.nftIds.length) revert LengthMismatch();
	}

	// YES I KNOW that this is inefficient, this is an owner facing function.
	// Legibility and clarity > once daily gas price.
	function validateBidWindows(AuctionParams memory _params) internal pure {
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
}
