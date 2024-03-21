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

		farm = new AuctioneerFarm(USD, GO, VOUCHER);
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

	function _farmDeposit(address user, uint256 pid, uint256 amount) public {
		vm.prank(user);
		farm.deposit(pid, amount, user);
	}
	function _farmWithdraw(address user, uint256 pid, uint256 amount) public {
		vm.prank(user);
		farm.withdraw(pid, amount, user);
	}
	function _injectFarmUSD(uint256 amount) public {
		vm.startPrank(user1);
		USD.approve(address(farm), amount);
		farm.receiveUsdDistribution(amount);
		vm.stopPrank();
	}

	uint256 user1Deposited = 5e18;
	uint256 user2Deposited = 15e18;
	uint256 user3Deposited = 0.75e18;
	uint256 user4Deposited = 2.8e18;
	uint256 totalDeposited = user1Deposited + user2Deposited + user3Deposited + user4Deposited;

	// ADMIN

	function test_add_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		farm.add(20000, GO_LP);
	}

	function test_add_RevertWhen_AlreadyAdded() public {
		farm.add(20000, GO_LP);

		vm.expectRevert(IAuctioneerFarm.AlreadyAdded.selector);
		farm.add(20000, GO_LP);
	}

	function test_add_ExpectEmit_AddedStakingToken() public {
		vm.expectEmit(true, true, true, true);
		emit AddedPool(goLpPid, 20000, address(GO_LP));

		farm.add(20000, GO_LP);
	}

	function test_add_Should_AddPool() public {
		uint256 poolCount = farm.poolLength();
		assertEq(poolCount, 1, "Should only have GO pool");

		farm.add(20000, GO_LP);

		poolCount = farm.poolLength();
		assertEq(poolCount, 2, "Should have GO & GO_LP pools");
		assertEq(address(farm.getPool(goLpPid).token), address(GO_LP), "GO_LP staking token should be initialized");
		assertEq(farm.getPool(goLpPid).allocPoint, 20000, "GO_LP allocPoint should be 20000");
		assertEq(farm.getPool(goLpPid).supply, 0, "GO_LP supply should be 0");
	}

	function test_add_deposit_ExpectEmit_Deposit() public {
		vm.expectRevert(IAuctioneerFarm.InvalidPid.selector);
		_farmDeposit(user1, goLpPid, 2e18);

		farm.add(20000, GO_LP);

		vm.expectEmit(true, true, true, true);
		emit Deposit(user1, goLpPid, 2e18, user1);
		_farmDeposit(user1, goLpPid, 2e18);
	}

	function test_set_RevertWhen_CallerIsNotOwner() public {
		farm.add(20000, GO_LP);

		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		farm.set(goLpPid, 0);
	}

	function test_set_ExpectEmit_UpdatedPool() public {
		farm.add(20000, GO_LP);

		vm.expectEmit(true, true, true, true);
		emit UpdatedPool(goLpPid, 0);

		farm.set(goLpPid, 0);
	}

	function test_set_Should_UpdateAllocPoint() public {
		farm.add(20000, GO_LP);

		assertEq(farm.getPool(goLpPid).allocPoint, 20000, "GO_LP alloc point initial value should be 20000");

		farm.set(goLpPid, 0);

		assertEq(farm.getPool(goLpPid).allocPoint, 0, "GO_LP allocPoint should be 0");
	}

	function test_set_withdraw_ExpectEmit_Withdraw() public {
		farm.add(20000, GO_LP);

		_farmDeposit(user1, goLpPid, 2e18);

		farm.set(goLpPid, 0);

		vm.expectEmit(true, true, true, true);
		emit Withdraw(user1, goLpPid, 2e18, user1);
		_farmWithdraw(user1, goLpPid, 2e18);
	}

	uint256[4] userGOStaked = [15e18, 3.5e18, 0, 0];
	uint256[4] userGO_LPStaked = [4e18, 0.25e18, 0, 0];
	uint256[4] userXXTokenStaked = [3e18, 13e18, 0, 0];
	uint256[4] userYYTokenStaked = [2e18, 3.33e18, 0, 0];

	uint256 GOAlloc = 10000;
	uint256 GO_LPAlloc = 20000;
	uint256 XXTokenAlloc = 15000;
	uint256 YYTokenAlloc = 25000;

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
			((userGOStaked[userIndex] * GOAlloc) +
				(userGO_LPStaked[userIndex] * GO_LPAlloc) +
				(userXXTokenStaked[userIndex] * XXTokenAlloc) +
				(userYYTokenStaked[userIndex] * YYTokenAlloc)) / 10000;
	}

	function _farmAddLpTokens(bool addGO_LP, bool addXXToken, bool addYYToken) internal {
		if (addGO_LP) farm.add(GO_LPAlloc, GO_LP);
		if (addXXToken) farm.add(XXTokenAlloc, XXToken);
		if (addYYToken) farm.add(YYTokenAlloc, YYToken);
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
		if (depositGO) _farmDeposit(user, goPid, userGOStaked[userIndex]);
		if (depositGO_LP) _farmDeposit(user, goLpPid, userGO_LPStaked[userIndex]);
		if (depositXX) _farmDeposit(user, xxPid, userXXTokenStaked[userIndex]);
		if (depositYY) _farmDeposit(user, yyPid, userYYTokenStaked[userIndex]);
	}
	function _farmDepositAllTokens(address user) internal {
		_farmDepositTokens(user, true, true, true, true);
	}

	// EQUALIZED USER STAKES
	function test_getEqualizedStaked_Should_UpdateWithAllocs() public {
		_farmAddAllLpTokens();

		_farmDepositAllTokens(user1);
		_farmDepositAllTokens(user2);

		uint256 expectedEqualizedUser1Staked = _getExpectedEqualizedStaked(user1);
		uint256 expectedEqualizedUser2Staked = _getExpectedEqualizedStaked(user2);

		uint256 expectedEqualizedTotalStaked = expectedEqualizedUser1Staked + expectedEqualizedUser2Staked;

		assertEq(expectedEqualizedUser1Staked, farm.getEqualizedUserStaked(user1), "User1 equalized staked correct");
		assertEq(expectedEqualizedUser2Staked, farm.getEqualizedUserStaked(user2), "User2 equalized staked correct");
		assertEq(expectedEqualizedTotalStaked, farm.getEqualizedTotalStaked(), "Total equalized staked correct");

		GO_LPAlloc = 17000;
		XXTokenAlloc = 22000;
		YYTokenAlloc = 19500;
		farm.set(goLpPid, GO_LPAlloc);
		farm.set(xxPid, XXTokenAlloc);
		farm.set(yyPid, YYTokenAlloc);

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

	// UPDATE goPerShare
	function test_add_Should_UpdateGoPerShare() public {
		_farmAddLpTokens(true, false, false);
		_farmDepositTokens(user1, true, true, false, false);
		_farmDepositTokens(user2, true, true, false, false);

		vm.warp(block.timestamp + 1 days);

		uint256 expectedGoPerShare = farm.getPoolUpdated(goPid).accGoPerShare;

		farm.add(XXTokenAlloc, XXToken);
		farm.add(YYTokenAlloc, YYToken);

		assertEq(farm.getPool(goPid).accGoPerShare, expectedGoPerShare, "goPerShare updated during add pools");
	}
	function test_set_Should_UpdateGoPerShare() public {
		_farmAddAllLpTokens();
		_farmDepositAllTokens(user1);
		_farmDepositAllTokens(user2);

		vm.warp(block.timestamp + 1 days);

		uint256 expectedGoPerShare = farm.getPoolUpdated(goPid).accGoPerShare;

		farm.set(xxPid, 0);
		farm.set(yyPid, 0);

		assertEq(farm.getPool(goPid).accGoPerShare, expectedGoPerShare, "goPerShare updated during set");
	}

	// PENDING

	function test_add_Should_PendingRemainConstant() public {
		_farmAddLpTokens(true, false, false);

		_farmDepositTokens(user1, true, true, false, false);
		_farmDepositTokens(user2, true, true, false, false);

		vm.warp(block.timestamp + 1 days);

		PendingAmounts memory user1PendingInit = farm.allPending(user1);
		PendingAmounts memory user2PendingInit = farm.allPending(user2);

		farm.add(XXTokenAlloc, XXToken);
		farm.add(YYTokenAlloc, YYToken);

		PendingAmounts memory user1PendingFinal = farm.allPending(user1);
		PendingAmounts memory user2PendingFinal = farm.allPending(user2);

		assertEq(user1PendingInit.go, user1PendingFinal.go, "User 1 pending go not affected by add");
		assertEq(user2PendingInit.go, user2PendingFinal.go, "User 2 pending go not affected by add");
	}

	function test_set_Should_PendingRemainConstant() public {
		_farmAddAllLpTokens();

		_farmDepositAllTokens(user1);
		_farmDepositAllTokens(user2);

		vm.warp(block.timestamp + 1 days);

		PendingAmounts memory user1PendingInit = farm.allPending(user1);
		PendingAmounts memory user2PendingInit = farm.allPending(user2);

		farm.set(xxPid, 0);
		farm.set(yyPid, 0);

		PendingAmounts memory user1PendingFinal = farm.allPending(user1);
		PendingAmounts memory user2PendingFinal = farm.allPending(user2);

		assertEq(user1PendingInit.go, user1PendingFinal.go, "User 1 pending go not affected by set");
		assertEq(user2PendingInit.go, user2PendingFinal.go, "User 2 pending go not affected by set");
	}
}
