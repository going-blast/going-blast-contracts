// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

enum EmissionType {
	DRIP, // Emission drips over time (GO, BID)
	CHUNK // Emission is added in chunks (USD)
}

struct StakingTokenOnlyData {
	address token;
	uint256 boost;
	uint256 total;
}
struct StakingTokenData {
	IERC20 token;
	uint256 boost;
	uint256 total;
	mapping(address => uint256) userStaked;
	mapping(address => uint256) emissionRewPerShare;
	mapping(address => mapping(address => uint256)) userEmissionDebt;
}
struct PendingAmounts {
	uint256 usd;
	uint256 go;
	uint256 bid;
}
struct StakingTokenRewPerShare {
	address stakingToken;
	address emissionToken;
	uint256 rewPerShare;
}

struct TokenEmission {
	address token; // Initialization check
	EmissionType emissionType;
	uint256 rewPerSecond;
	uint256 lastRewardTimestamp;
	uint256 emissionFinalTimestamp;
}

interface AuctioneerFarmEvents {
	event InitializedGOEmission(uint256 _goPerSecond, uint256 _duration);
	event UpdatedBIDEmission(uint256 _bidPerSecond, uint256 _duration);
	event AddedStakingToken(address indexed _token, uint256 _boost);
	event UpdatedLpBoost(address indexed _token, uint256 _boost);
	event ReceivedUSDDistribution(uint256 _amount);

	event Deposit(address indexed _user, address indexed _token, uint256 _amount);
	event Withdraw(address indexed _user, address indexed _token, uint256 _amount);
	event Harvested(address indexed _user, PendingAmounts _pending);
}

interface IAuctioneerFarm {
	error BadWithdrawal();
	error BadDeposit();
	error NotStakingToken();
	error OutsideRange();
	error NotEnoughEmissionToken();
	error AlreadySet();
	error AlreadyAdded();
	error AlreadyInitializedEmissions();

	function receiveUSDDistribution(uint256 _amount) external returns (bool);
	function getEqualizedUserStaked(address _user) external view returns (uint256);
}
