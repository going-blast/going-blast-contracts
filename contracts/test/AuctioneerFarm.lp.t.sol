// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { Auctioneer } from "../Auctioneer.sol";
import "../IAuctioneer.sol";
import { GOToken } from "../GOToken.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BasicERC20 } from "../BasicERC20.sol";
import { WETH9 } from "../WETH9.sol";
import "../IAuctioneerFarm.sol";

contract AuctioneerFarmLpTest is AuctioneerHelper, AuctioneerFarmEvents {
	using SafeERC20 for IERC20;

	uint256 public farmGO;

	function setUp() public override {
		super.setUp();

		farm = new AuctioneerFarm(USD, GO, BID);
		auctioneer.setTreasury(treasury);

		// Distribute GO
		GO.safeTransfer(address(auctioneer), (GO.totalSupply() * 6000) / 10000);
		GO.safeTransfer(presale, (GO.totalSupply() * 2000) / 10000);
		GO.safeTransfer(treasury, (GO.totalSupply() * 1000) / 10000);
		GO.safeTransfer(liquidity, (GO.totalSupply() * 500) / 10000);
		farmGO = (GO.totalSupply() * 500) / 10000;
		GO.safeTransfer(address(farm), farmGO);

		// Initialize after receiving GO token
		auctioneer.initialize(_getNextDay2PMTimestamp());

		// Give WETH to treasury
		vm.deal(treasury, 10e18);

		// Treasury deposit for WETH
		vm.prank(treasury);
		WETH.deposit{ value: 5e18 }();

		// Approve WETH for auctioneer
		vm.prank(treasury);
		IERC20(address(WETH)).approve(address(auctioneer), type(uint256).max);

		for (uint8 i = 0; i < 4; i++) {
			address user = i == 0
				? user1
				: i == 1
					? user2
					: i == 2
						? user3
						: user4;

			// Give tokens
			vm.prank(presale);
			GO.transfer(user, 50e18);
			USD.mint(user, 1000e18);
			GO_LP.mint(user, 50e18);
			XXToken.mint(user, 50e18);
			YYToken.mint(user, 50e18);

			// Approve
			vm.startPrank(user);
			USD.approve(address(auctioneer), 1000e18);
			GO.approve(address(farm), 1000e18);
			GO_LP.approve(address(farm), 1000e18);
			XXToken.approve(address(farm), 1000e18);
			YYToken.approve(address(farm), 1000e18);
			vm.stopPrank();
		}

		// Create auction
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createDailyAuctions(params);

		// Initialize farm emissions
		farm.initializeEmissions(farmGO, 180 days);
	}

	function _farmDeposit(address user, address token, uint256 amount) public {
		vm.prank(user);
		farm.deposit(token, amount);
	}
	function _farmWithdraw(address user, address token, uint256 amount) public {
		vm.prank(user);
		farm.withdraw(token, amount);
	}
	function _injectFarmUSD(uint256 amount) public {
		vm.startPrank(user1);
		USD.approve(address(farm), amount);
		farm.receiveUSDDistribution(amount);
		vm.stopPrank();
	}

	uint256 user1Deposited = 5e18;
	uint256 user2Deposited = 15e18;
	uint256 user3Deposited = 0.75e18;
	uint256 user4Deposited = 2.8e18;
	uint256 totalDeposited = user1Deposited + user2Deposited + user3Deposited + user4Deposited;

	// ADMIN

	function test_addLp_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		farm.addLp(address(GO_LP), 20000);
	}

	function test_addLp_RevertWhen_AlreadyAdded() public {
		farm.addLp(address(GO_LP), 20000);

		vm.expectRevert(IAuctioneerFarm.AlreadyAdded.selector);
		farm.addLp(address(GO_LP), 20000);
	}

	function test_addLp_RevertWhen_OutsideRange() public {
		vm.expectRevert(IAuctioneerFarm.OutsideRange.selector);
		farm.addLp(address(GO_LP), 9999);

		vm.expectRevert(IAuctioneerFarm.OutsideRange.selector);
		farm.addLp(address(GO_LP), 30001);
	}

	function test_addLp_ExpectEmit_AddedStakingToken() public {
		vm.expectEmit(true, true, true, true);
		emit AddedStakingToken(address(GO_LP), 20000);

		farm.addLp(address(GO_LP), 20000);
	}

	function test_addLp_Should_SetStakingTokenData() public {
		address[] memory stakingTokens = farm.getStakingTokens();
		assertEq(stakingTokens.length, 1, "Should only have GO staking token");
		assertEq(
			farm.getStakingTokenData(address(GO_LP)).token,
			address(0),
			"GO_LP staking token data should not be initialized"
		);

		farm.addLp(address(GO_LP), 20000);

		stakingTokens = farm.getStakingTokens();
		assertEq(stakingTokens.length, 2, "Should have GO & GO_LP staking token");
		assertEq(
			farm.getStakingTokenData(address(GO_LP)).token,
			address(GO_LP),
			"GO_LP staking token should be initialized"
		);
		assertEq(farm.getStakingTokenData(address(GO_LP)).boost, 20000, "GO_LP boost should be 20000");
		assertEq(farm.getStakingTokenData(address(GO_LP)).total, 0, "GO_LP total should be 0");
	}

	function test_addLp_deposit_ExpectEmit_Deposit() public {
		vm.expectRevert(IAuctioneerFarm.NotStakingToken.selector);
		_farmDeposit(user1, address(GO_LP), 2e18);

		farm.addLp(address(GO_LP), 20000);

		vm.expectEmit(true, true, true, true);
		emit Deposit(user1, address(GO_LP), 2e18);
		_farmDeposit(user1, address(GO_LP), 2e18);
	}

	function test_removeLp_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		farm.removeLp(address(GO_LP));
	}

	function test_removeLp_ExpectEmit_UpdatedLpBoost() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedLpBoost(address(GO_LP), 0);

		farm.removeLp(address(GO_LP));
	}

	function test_removeLp_Should_UpdateStakingTokenData() public {
		farm.removeLp(address(GO_LP));

		assertEq(farm.getStakingTokenData(address(GO_LP)).boost, 0, "GO_LP boost should be 0");
	}

	function test_removeLp_withdraw_ExpectEmit_Withdraw() public {
		farm.addLp(address(GO_LP), 20000);

		_farmDeposit(user1, address(GO_LP), 2e18);

		farm.removeLp(address(GO_LP));

		vm.expectEmit(true, true, true, true);
		emit Withdraw(user1, address(GO_LP), 2e18);
		_farmWithdraw(user1, address(GO_LP), 2e18);
	}

	function test_updateLpBoost_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		farm.updateLpBoost(address(GO_LP), 20000);
	}

	function test_updateLpBoost_RevertWhen_OutsideRange() public {
		farm.addLp(address(GO_LP), 20000);

		vm.expectRevert(IAuctioneerFarm.OutsideRange.selector);
		farm.updateLpBoost(address(GO_LP), 9999);

		vm.expectRevert(IAuctioneerFarm.OutsideRange.selector);
		farm.updateLpBoost(address(GO_LP), 30001);
	}

	function test_updateLpBoost_ExpectEmit_UpdatedLpBoost() public {
		farm.addLp(address(GO_LP), 20000);

		vm.expectEmit(true, true, true, true);
		emit UpdatedLpBoost(address(GO_LP), 15000);

		farm.updateLpBoost(address(GO_LP), 15000);
	}

	function test_updateLpBoost_Should_SetStakingTokenData() public {
		farm.addLp(address(GO_LP), 20000);

		assertEq(farm.getStakingTokenData(address(GO_LP)).boost, 20000, "GO_LP boost should be 20000");

		farm.updateLpBoost(address(GO_LP), 25000);

		assertEq(farm.getStakingTokenData(address(GO_LP)).boost, 25000, "GO_LP boost should be 25000");
	}

	uint256[4] userGOStaked = [15e18, 3.5e18, 0, 0];
	uint256[4] userGO_LPStaked = [4e18, 0.25e18, 0, 0];
	uint256[4] userXXTokenStaked = [3e18, 13e18, 0, 0];
	uint256[4] userYYTokenStaked = [2e18, 3.33e18, 0, 0];

	uint256 GOBonus = 10000;
	uint256 GO_LPBonus = 20000;
	uint256 XXTokenBonus = 15000;
	uint256 YYTokenBonus = 25000;

	function _getUserIndex(address user) internal view returns (uint256) {
		return
			user == user1
				? 0
				: user == user2
					? 1
					: user == user3
						? 2
						: 3;
	}

	function _getExpectedEqualizedStaked(address user) internal view returns (uint256) {
		uint256 userIndex = _getUserIndex(user);
		return
			((userGOStaked[userIndex] * GOBonus) +
				(userGO_LPStaked[userIndex] * GO_LPBonus) +
				(userXXTokenStaked[userIndex] * XXTokenBonus) +
				(userYYTokenStaked[userIndex] * YYTokenBonus)) / 10000;
	}

	function _farmAddLpTokens(bool addGO_LP, bool addXXToken, bool addYYToken) internal {
		if (addGO_LP) farm.addLp(address(GO_LP), GO_LPBonus);
		if (addXXToken) farm.addLp(address(XXToken), XXTokenBonus);
		if (addYYToken) farm.addLp(address(YYToken), YYTokenBonus);
	}
	function _farmAddAllLpTokens() internal {
		_farmAddLpTokens(true, true, true);
	}

	function _farmDepositTokens(
		address user,
		bool depositGO,
		bool depositGO_LP,
		bool depositXX,
		bool depositYY
	) internal {
		uint256 userIndex = _getUserIndex(user);
		if (depositGO) _farmDeposit(user, address(GO), userGOStaked[userIndex]);
		if (depositGO_LP) _farmDeposit(user, address(GO_LP), userGO_LPStaked[userIndex]);
		if (depositXX) _farmDeposit(user, address(XXToken), userXXTokenStaked[userIndex]);
		if (depositYY) _farmDeposit(user, address(YYToken), userYYTokenStaked[userIndex]);
	}
	function _farmDepositAllTokens(address user) internal {
		_farmDepositTokens(user, true, true, true, true);
	}

	// EQUALIZED USER STAKES
	function test_getEqualizedStaked_Should_UpdateWithBoosts() public {
		_farmAddAllLpTokens();

		_farmDepositAllTokens(user1);
		_farmDepositAllTokens(user2);

		uint256 expectedEqualizedUser1Staked = _getExpectedEqualizedStaked(user1);
		uint256 expectedEqualizedUser2Staked = _getExpectedEqualizedStaked(user2);

		uint256 expectedEqualizedTotalStaked = expectedEqualizedUser1Staked + expectedEqualizedUser2Staked;

		assertEq(expectedEqualizedUser1Staked, farm.getEqualizedUserStaked(user1), "User1 equalized staked correct");
		assertEq(expectedEqualizedUser2Staked, farm.getEqualizedUserStaked(user2), "User2 equalized staked correct");
		assertEq(expectedEqualizedTotalStaked, farm.getEqualizedTotalStaked(), "Total equalized staked correct");

		GO_LPBonus = 17000;
		XXTokenBonus = 22000;
		YYTokenBonus = 19500;
		farm.updateLpBoost(address(GO_LP), GO_LPBonus);
		farm.updateLpBoost(address(XXToken), XXTokenBonus);
		farm.updateLpBoost(address(YYToken), YYTokenBonus);

		expectedEqualizedUser1Staked = _getExpectedEqualizedStaked(user1);
		expectedEqualizedUser2Staked = _getExpectedEqualizedStaked(user2);

		expectedEqualizedTotalStaked = expectedEqualizedUser1Staked + expectedEqualizedUser2Staked;

		assertEq(
			expectedEqualizedUser1Staked,
			farm.getEqualizedUserStaked(user1),
			"User1 equalized staked correct after boost update"
		);
		assertEq(
			expectedEqualizedUser2Staked,
			farm.getEqualizedUserStaked(user2),
			"User2 equalized staked correct after boost update"
		);
		assertEq(
			expectedEqualizedTotalStaked,
			farm.getEqualizedTotalStaked(),
			"Total equalized staked correct after boost update"
		);
	}

	// UPDATE goRewardPerShare
	function test_addLp_Should_UpdateGoRewardPerShare() public {
		_farmAddLpTokens(true, false, false);
		_farmDepositTokens(user1, true, true, false, false);
		_farmDepositTokens(user2, true, true, false, false);

		vm.warp(block.timestamp + 1 days);

		(, uint256 expectedGoRewardPerShare) = farm.getGOEmissions();

		farm.addLp(address(XXToken), XXTokenBonus);
		farm.addLp(address(YYToken), YYTokenBonus);

		(TokenEmission memory goEmission, ) = farm.getGOEmissions();
		assertEq(goEmission.rewPerShare, expectedGoRewardPerShare, "goRewardPerShare updated during addLp");
	}
	function test_removeLp_Should_UpdateGoRewardPerShare() public {
		_farmAddAllLpTokens();
		_farmDepositAllTokens(user1);
		_farmDepositAllTokens(user2);

		vm.warp(block.timestamp + 1 days);

		(, uint256 expectedGoRewardPerShare) = farm.getGOEmissions();

		farm.removeLp(address(XXToken));
		farm.removeLp(address(YYToken));

		(TokenEmission memory goEmission, ) = farm.getGOEmissions();
		assertEq(goEmission.rewPerShare, expectedGoRewardPerShare, "goRewardPerShare updated during removeLp");
	}
	function test_updateLpBoost_Should_UpdateGoRewardPerShare() public {
		_farmAddAllLpTokens();
		_farmDepositAllTokens(user1);
		_farmDepositAllTokens(user2);

		vm.warp(block.timestamp + 1 days);

		(, uint256 expectedGoRewardPerShare) = farm.getGOEmissions();

		farm.updateLpBoost(address(XXToken), XXTokenBonus);
		farm.updateLpBoost(address(YYToken), YYTokenBonus);

		(TokenEmission memory goEmission, ) = farm.getGOEmissions();
		assertEq(goEmission.rewPerShare, expectedGoRewardPerShare, "goRewardPerShare updated during updateLpBoost");
	}

	// PENDING

	function test_addLp_Should_PendingRemainConstant() public {
		_farmAddLpTokens(true, false, false);

		_farmDepositTokens(user1, true, true, false, false);
		_farmDepositTokens(user2, true, true, false, false);

		vm.warp(block.timestamp + 1 days);

		PendingAmounts memory user1PendingInit = farm.pending(user1);
		PendingAmounts memory user2PendingInit = farm.pending(user2);

		farm.addLp(address(XXToken), XXTokenBonus);
		farm.addLp(address(YYToken), YYTokenBonus);

		PendingAmounts memory user1PendingFinal = farm.pending(user1);
		PendingAmounts memory user2PendingFinal = farm.pending(user2);

		assertEq(user1PendingInit.go, user1PendingFinal.go, "User 1 pending go not affected by addLp");
		assertEq(user2PendingInit.go, user2PendingFinal.go, "User 2 pending go not affected by addLp");
	}

	function test_removeLp_Should_PendingRemainConstant() public {
		_farmAddAllLpTokens();

		_farmDepositAllTokens(user1);
		_farmDepositAllTokens(user2);

		vm.warp(block.timestamp + 1 days);

		(TokenEmission memory goEmission, uint256 updatedGOPerShare) = farm.getGOEmissions();
		console.log("Rew per share actual %s, updated %s", goEmission.rewPerShare, updatedGOPerShare);
		PendingAmounts memory user1PendingInit = farm.pending(user1);
		PendingAmounts memory user2PendingInit = farm.pending(user2);

		farm.removeLp(address(XXToken));
		farm.removeLp(address(YYToken));

		PendingAmounts memory user1PendingFinal = farm.pending(user1);
		PendingAmounts memory user2PendingFinal = farm.pending(user2);

		(goEmission, ) = farm.getGOEmissions();
		console.log("Rew Per Share", goEmission.rewPerShare);
		assertEq(user1PendingInit.go, user1PendingFinal.go, "User 1 pending go not affected by removeLp");
		assertEq(user2PendingInit.go, user2PendingFinal.go, "User 2 pending go not affected by removeLp");
	}

	function test_updateLpBoost_Should_PendingRemainConstant() public {
		_farmAddAllLpTokens();

		_farmDepositAllTokens(user1);
		_farmDepositAllTokens(user2);

		vm.warp(block.timestamp + 1 days);

		PendingAmounts memory user1PendingInit = farm.pending(user1);
		PendingAmounts memory user2PendingInit = farm.pending(user2);

		GO_LPBonus = 17000;
		XXTokenBonus = 22000;
		YYTokenBonus = 19500;
		farm.updateLpBoost(address(GO_LP), GO_LPBonus);
		farm.updateLpBoost(address(XXToken), XXTokenBonus);
		farm.updateLpBoost(address(YYToken), YYTokenBonus);

		PendingAmounts memory user1PendingFinal = farm.pending(user1);
		PendingAmounts memory user2PendingFinal = farm.pending(user2);

		assertEq(user1PendingInit.go, user1PendingFinal.go, "User 1 pending go not affected by updateLpBoost");
		assertEq(user2PendingInit.go, user2PendingFinal.go, "User 2 pending go not affected by updateLpBoost");
	}
}
