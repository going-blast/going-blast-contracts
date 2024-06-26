// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

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
				abi.encode(
					PERMIT_TYPEHASH,
					_permit.owner,
					_permit.spender,
					_permit.value,
					_permit.nonce,
					_permit.deadline
				)
			);
	}

	// computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
	function getTypedDataHash(Permit memory _permit, bytes32 DOMAIN_SEPARATOR) public pure returns (bytes32) {
		return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, getStructHash(_permit)));
	}
}

contract AuctioneerPermitTest is AuctioneerHelper {
	using SafeERC20 for IERC20;

	SigUtils public sigUtils;

	function setUp() public override {
		super.setUp();
		sigUtils = new SigUtils();

		_setupAuctioneerTreasury();
		_setupAuctioneerCreator();
		_giveUsersTokensAndApprove();
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

	function test_auctioneer_bidWithPermit_VOUCHER() public {
		_warpToUnlockTimestamp(0);

		_giveVoucher(user1, 10e18);

		assertEq(VOUCHER.allowance(user1, address(auctioneer)), 0, "User1 not approved VOUCHER for auctioneer");

		PermitData memory permitData = getPermitData(user1, user1PK, address(auctioneer), address(VOUCHER), 10e18);

		_expectTokenTransfer(VOUCHER, user1, dead, 1e18);
		_expectEmitAuctionEvent_Bid(user1, 0, 0, "Hello World", 1);

		vm.prank(user1);
		auctioneer.bidWithPermit(0, 0, "Hello World", 1, PaymentType.VOUCHER, permitData);

		assertEq(auctioneer.getAuctionUser(0, user1).bids, 1, "User has bid");
		assertEq(VOUCHER.allowance(user1, address(auctioneer)), 9e18, "User1 approved VOUCHER for auctioneer");
	}
}
