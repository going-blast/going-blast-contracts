// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract GoingBlastAirdrop is Ownable, ReentrancyGuard {
	using SafeERC20 for IERC20;

	address public voucher;
	address public voucherOwner;
	uint256 public expirationTimestamp;
	bool public closed;

	struct UserData {
		uint256 amount;
		uint256 claimed;
	}
	mapping(address => UserData) public users;

	constructor(address _voucher, address _voucherOwner, uint256 _expirationTimestamp) Ownable(msg.sender) {
		voucher = _voucher;
		voucherOwner = _voucherOwner;
		expirationTimestamp = _expirationTimestamp;
	}

	event Closed(bool _closed);
	event TokensClaimed(address indexed _claimer, address indexed _to, uint256 _amount);

	error ClaimZero();
	error ClaimExceeded();
	error AirdropClosed();
	error LengthMismatch();

	function close(bool _closed) external onlyOwner {
		closed = _closed;
		emit Closed(_closed);
	}

	function addUserAirdrops(address[] calldata addresses, uint256[] calldata amounts) external onlyOwner {
		if (addresses.length != amounts.length) revert LengthMismatch();
		for (uint256 i = 0; i < addresses.length; i++) {
			users[addresses[i]].amount += amounts[i];
		}
	}

	function claim(uint256 _amount, address _to) external nonReentrant {
		verifyClaim(msg.sender, _amount);
		_transferClaimedTokens(_to, _amount);
		emit TokensClaimed(msg.sender, _to, _amount);
	}

	function verifyClaim(address _claimer, uint256 _amount) public view {
		uint256 availableAmount = users[_claimer].amount;

		if (_amount == 0) revert ClaimZero();
		if (_amount > availableAmount) revert ClaimExceeded();
		if (expirationTimestamp != 0 && expirationTimestamp <= block.timestamp) revert AirdropClosed();
		if (closed) revert AirdropClosed();
	}

	function _transferClaimedTokens(address _to, uint256 _quantityBeingClaimed) internal {
		IERC20(voucher).safeTransferFrom(voucherOwner, _to, _quantityBeingClaimed);
		users[msg.sender].claimed += _quantityBeingClaimed;
		users[msg.sender].amount -= _quantityBeingClaimed;
	}

	function claimable(address _claimer) public view returns (UserData memory user) {
		user = users[_claimer];
	}
}
