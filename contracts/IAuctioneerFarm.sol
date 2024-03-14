// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

struct UserDebts {
	uint256 debtGO;
	uint256 debtUSD;
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
}

interface AuctioneerFarmEvents {
	event InitializedGOEmission(uint256 _goPerSecond);
	event AddedStakingToken(address indexed _token, uint256 _boost);
	event UpdatedLpBoost(address indexed _token, uint256 _boost);
	event ReceivedUSDDistribution(uint256 _amount);

	event Deposit(address indexed _user, address indexed _token, uint256 _amount);
	event Withdraw(address indexed _user, address indexed _token, uint256 _amount);
	event Harvested(address indexed _user, uint256 _usdHarvested, uint256 _goHarvested);
}

interface IAuctioneerFarm {
	error BadWithdrawal();
	error BadDeposit();
	error NotStakingToken();
	error OutsideRange();
	error NotEnoughGo();
	error AlreadySet();
	error AlreadyAdded();
	error AlreadyInitializedEmissions();

	function receiveUSDDistribution(uint256 _amount) external returns (bool);
	function getEqualizedUserStaked(address _user) external view returns (uint256);
}
