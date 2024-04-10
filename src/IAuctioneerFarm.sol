// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

struct PendingAmounts {
	uint256 go;
	uint256 voucher;
	uint256 usd;
}

struct TokenEmission {
	IERC20 token;
	uint256 perSecond;
	uint256 endTimestamp;
}

struct UserInfo {
	uint256 amount;
	uint256 goDebt;
	uint256 voucherDebt;
	uint256 usdDebt;
	uint256 goUnlockTimestamp;
}

struct PoolInfo {
	uint256 pid;
	IERC20 token;
	uint256 supply;
	uint256 allocPoint;
	uint256 lastRewardTimestamp;
	uint256 accGoPerShare;
	uint256 accVoucherPerShare;
	uint256 accUsdPerShare;
}

interface AuctioneerFarmEvents {
	event SetEmission(address indexed _token, uint256 _perSecond, uint256 _duration);
	event AddedPool(uint256 _pid, uint256 _allocPoint, address indexed _token);
	event UpdatedPool(uint256 _pid, uint256 _allocPoint);

	event ReceivedUsdDistribution(uint256 _amount);

	event Deposit(address indexed _user, uint256 _pid, uint256 _amount, address _to);
	event Withdraw(address indexed _user, uint256 _pid, uint256 _amount, address _to);
	event Harvest(address indexed _user, uint256 _pid, PendingAmounts _pending, address _to);
	event EmergencyWithdraw(address indexed _user, uint256 _pid, uint256 _amount, address _to);
}

interface IAuctioneerFarm {
	error BadWithdrawal();
	error BadDeposit();
	error NotEnoughEmissionToken();
	error AlreadyAdded();
	error AlreadyInitializedEmissions();
	error InvalidPid();
	error GoLocked();

	function link() external;
	function depositLockedGo(uint256 amount, address user, uint256 lockDuration) external;
	function receiveUsdDistribution(uint256 _amount) external returns (bool);
	function getEqualizedUserStaked(address _user) external view returns (uint256);
}
