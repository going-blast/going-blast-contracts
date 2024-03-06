// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4;

import "./IAuctioneer.sol";


library AuctionUtils {

  function min(uint256 a, uint256 b) internal pure returns (uint256) {
    return a < b ? a : b;
  }
  function max(uint256 a, uint256 b) internal pure returns (uint256) {
    return a > b ? a : b;
  }

  function finalize(Auction storage auction) internal {
    auction.finalized = true;
  }

  function activeWindow(Auction storage auction) internal view returns (int8) {
    // Before auction opens, active window is -1
    if (block.timestamp < auction.unlockTimestamp) return -1;
    
    // Check if timestamp is before the end of each window, if it is, return that windows index
    for (uint8 i = 0; i < auction.windows.length; i++) {
      if (block.timestamp < auction.windows[i].windowCloseTimestamp) return int8(i);
    }

    // Shouldn't ever get here, maybe in 10 years or so.
    return int8(uint8(auction.windows.length - 1));
  }

  function isBiddingOpen(Auction storage auction) internal view returns (bool) {
    // Early escape if the auction has been finalized
    if (auction.finalized) return false;

    int8 window = activeWindow(auction);

    if (window == -1) return false;
    if (auction.windows[uint8(window)].windowType == BidWindowType.OPEN) return true;

    uint256 closesAtTimestamp = max(auction.windows[uint8(window)].windowOpenTimestamp, auction.bidTimestamp);

    return block.timestamp < closesAtTimestamp;
  }
  function validateBiddingOpen(Auction storage auction) internal view {
    if (!isBiddingOpen(auction)) revert BiddingClosed();
  }

  function isClosed(Auction storage auction) internal view returns (bool) {
    // Early escape if the auction has been finalized
    if (auction.finalized) return true;

    int8 window = activeWindow(auction);

    if (window == -1) return false;
    if (auction.windows[uint8(window)].windowType == BidWindowType.OPEN) return false;

    uint256 closesAtTimestamp = max(auction.windows[uint8(window)].windowOpenTimestamp, auction.bidTimestamp);

    return block.timestamp > closesAtTimestamp;
  }
  function validateEnded(Auction storage auction) internal view {
    if (!isClosed(auction)) revert AuctionStillRunning();
  }




  function addBidWindows(Auction storage auction, AuctionParams memory _params, uint256 _bonusTime) internal {
    uint256 openTimestamp = _params.unlockTimestamp;

    for (uint8 i = 0; i < _params.windows.length; i++) {
      uint256 closeTimestamp = openTimestamp + _params.windows[i].duration;
      if (_params.windows[i].windowType == BidWindowType.INFINITE) {
        closeTimestamp = openTimestamp + 315600000; // 10 years, hah
      }

      auction.windows.push(BidWindow({
        windowType: _params.windows[i].windowType,
        windowOpenTimestamp: openTimestamp,
        windowCloseTimestamp: closeTimestamp,
        timer: _params.windows[i].timer + _bonusTime
      }));

      openTimestamp += _params.windows[i].duration;
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
    if (_params.windows[_params.windows.length - 1].windowType != BidWindowType.INFINITE) revert LastWindowNotInfinite();

    // VALIDATE: Only one infinite window can exist
    uint8 infCount = 0;
    for (uint8 i = 0; i < _params.windows.length; i++) {
      if (_params.windows[i].windowType == BidWindowType.INFINITE) infCount += 1;
    }
    if (infCount > 1) revert MultipleInfiniteWindows();

    // VALIDATE: Windows must have a valid duration (if not infinite)
    for (uint8 i = 0; i < _params.windows.length; i++) {
      if (_params.windows[i].windowType != BidWindowType.INFINITE && _params.windows[i].duration < 1 hours) revert WindowTooShort();
    }

    // VALIDATE: Timed windows must have a valid timer
    for (uint8 i = 0; i < _params.windows.length; i++) {
      if (_params.windows[i].windowType != BidWindowType.OPEN && _params.windows[i].timer < 60 seconds) revert InvalidBidWindowTimer();
    }
  }
}

