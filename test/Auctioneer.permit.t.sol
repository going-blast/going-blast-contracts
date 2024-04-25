// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "../src/IAuctioneerFarm.sol";

contract SigUtils {
	// keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
	bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

	struct Permit {
		address owner;
		address spender;
		uint256 value;
		uint256 nonce;
		uint256 deadline;
	}

	// computes the hash of a permit
	function getStructHash(Permit memory _permit) internal pure returns (bytes32) {
		return
			keccak256(
				abi.encode(PERMIT_TYPEHASH, _permit.owner, _permit.spender, _permit.value, _permit.nonce, _permit.deadline)
			);
	}

	// computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
	function getTypedDataHash(Permit memory _permit, bytes32 DOMAIN_SEPARATOR) public pure returns (bytes32) {
		return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, getStructHash(_permit)));
	}
}

contract AuctioneerPermitTest is AuctioneerHelper, AuctioneerFarmEvents {
	using SafeERC20 for IERC20;

	SigUtils public sigUtils;

	function setUp() public override {
		super.setUp();
		sigUtils = new SigUtils();

		_distributeGO();
		_initializeAuctioneerEmissions();
		_setupAuctioneerTreasury();
		_giveUsersTokensAndApprove();
		_auctioneerUpdateFarm();
		_initializeFarmEmissions();
		_initializeFarmVoucherEmissions();
		_createDefaultDay1Auction();
	}

	// Utils
	function getPermitData(
		address owner,
		uint256 ownerPK,
		address spender,
		address token,
		uint256 value
	) internal view returns (PermitData memory permitData) {
		SigUtils.Permit memory permit = SigUtils.Permit({
			owner: owner,
			spender: spender,
			value: value,
			nonce: 0,
			deadline: 1 days
		});

		bytes32 digest = sigUtils.getTypedDataHash(permit, IERC20Permit(token).DOMAIN_SEPARATOR());

		permitData.token = token;
		permitData.value = value;
		permitData.deadline = permit.deadline;
		(permitData.v, permitData.r, permitData.s) = vm.sign(ownerPK, digest);
	}

	// Auctioneer

	function test_auctioneer_bidWithPermit_USD() public {
		_warpToUnlockTimestamp(0);

		// Remove allowance
		vm.prank(user1);
		USD.approve(address(auctioneer), 0);
		assertEq(USD.allowance(user1, address(auctioneer)), 0, "User1 not approved USD for auctioneer");

		uint256 expectedBid = auctioneerAuction.startingBid() + auctioneerAuction.bidIncrement();
		BidOptions memory options = BidOptions({
			paymentType: PaymentType.WALLET,
			multibid: 1,
			message: "Hello World",
			rune: 0
		});
		PermitData memory permitData = getPermitData(user1, user1PK, address(auctioneer), address(USD), 100e18);

		_expectTokenTransfer(USD, user1, address(auctioneer), 1e18);

		vm.expectEmit(true, true, true, true);
		emit Bid(0, user1, expectedBid, "", options, block.timestamp);

		vm.prank(user1);
		auctioneer.bidWithPermit(0, options, permitData);

		assertEq(auctioneerUser.getAuctionUser(0, user1).bids, 1, "User has bid");
		assertEq(USD.allowance(user1, address(auctioneer)), 99e18, "User1 approved USD for auctioneer");
	}

	function test_auctioneer_bidWithPermit_VOUCHER() public {
		_warpToUnlockTimestamp(0);

		_giveVoucher(user1, 10e18);

		assertEq(VOUCHER.allowance(user1, address(auctioneer)), 0, "User1 not approved VOUCHER for auctioneer");

		uint256 expectedBid = auctioneerAuction.startingBid() + auctioneerAuction.bidIncrement();
		BidOptions memory options = BidOptions({
			paymentType: PaymentType.VOUCHER,
			multibid: 1,
			message: "Hello World",
			rune: 0
		});
		PermitData memory permitData = getPermitData(user1, user1PK, address(auctioneer), address(VOUCHER), 10e18);

		_expectTokenTransfer(VOUCHER, user1, dead, 1e18);

		vm.expectEmit(true, true, true, true);
		emit Bid(0, user1, expectedBid, "", options, block.timestamp);

		vm.prank(user1);
		auctioneer.bidWithPermit(0, options, permitData);

		assertEq(auctioneerUser.getAuctionUser(0, user1).bids, 1, "User has bid");
		assertEq(VOUCHER.allowance(user1, address(auctioneer)), 9e18, "User1 approved VOUCHER for auctioneer");
	}

	function test_auctioneer_claimLotWithPermit() public {
		_warpToUnlockTimestamp(0);
		_bid(user1);
		_warpToAuctionEndTimestamp(0);

		vm.prank(user1);
		USD.approve(address(auctioneer), 0);

		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;
		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(auctioneer), 0, lotPrice));

		vm.prank(user1);
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: true }));

		PermitData memory permitData = getPermitData(user1, user1PK, address(auctioneer), address(USD), 100e18);

		vm.expectEmit(true, true, true, true);
		TokenData[] memory tokens = new TokenData[](1);
		tokens[0] = TokenData({ token: ETH_ADDR, amount: 1e18 });
		NftData[] memory nfts = new NftData[](0);
		emit ClaimedLot(0, user1, 0, 1e18, tokens, nfts);

		vm.prank(user1);
		auctioneer.claimLotWithPermit(0, ClaimLotOptions({ paymentType: PaymentType.WALLET, unwrapETH: true }), permitData);
	}

	// AuctioneerUser

	function test_auctioneerUser_addFundsWithPermit() public {
		vm.prank(user1);
		USD.approve(address(auctioneerUser), 0);

		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(auctioneerUser), 0, 10e18));

		vm.prank(user1);
		auctioneerUser.addFunds(10e18);

		PermitData memory permitData = getPermitData(user1, user1PK, address(auctioneerUser), address(USD), 10e18);

		vm.expectEmit(true, true, true, true);
		emit AddedFunds(user1, 10e18);

		vm.prank(user1);
		auctioneerUser.addFundsWithPermit(10e18, permitData);
	}

	// AuctioneerFarm

	function test_auctioneerFarm_depositWithPermit_GO() public {
		vm.prank(user1);
		IERC20(GO).approve(address(farm), 0);

		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(farm), 0, 5e18));

		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		PermitData memory permitData = getPermitData(user1, user1PK, address(farm), address(GO), 5e18);

		vm.expectEmit(true, true, true, true);
		emit Deposit(user1, goPid, 5e18, user1);

		vm.prank(user1);
		farm.depositWithPermit(goPid, 5e18, user1, permitData);
	}

	function test_auctioneerFarm_depositWithPermit_GO_LP() public {
		farm.add(20000, GO_LP);

		vm.prank(user1);
		IERC20(GO_LP).approve(address(farm), 0);

		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(farm), 0, 5e18));

		vm.prank(user1);
		farm.deposit(goLpPid, 5e18, user1);

		PermitData memory permitData = getPermitData(user1, user1PK, address(farm), address(GO_LP), 5e18);

		vm.expectEmit(true, true, true, true);
		emit Deposit(user1, goLpPid, 5e18, user1);

		vm.prank(user1);
		farm.depositWithPermit(goLpPid, 5e18, user1, permitData);
	}
}
