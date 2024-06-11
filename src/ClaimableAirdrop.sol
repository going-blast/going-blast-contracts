// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract ClaimableAirdropMerkle is Ownable, ReentrancyGuard {
	using SafeERC20 for IERC20;

	IERC20 public token;
	address public tokenOwner;

	struct PartnerAirdrop {
		uint256 id;
		string partner;
		bool isFcfs;
		uint256 fcfsLimit;
		uint256 claimedCount;
		bytes32 merkleRoot;
		bool closed;
	}

	uint256 airdropCount;
	mapping(uint256 => PartnerAirdrop) public airdrops;
	mapping(uint256 => mapping(address => bool)) public airdropUserClaimed;

	event CreatedAirdrop(uint256 indexed id, string partner, bool isFcfs, uint256 fcfsLimit, bytes32 merkleRoot);
	event ClosedAirdrop(uint256 indexed id, bool closed);
	event Claimed(uint256 indexed id, address indexed to, uint256 amount);

	error InvalidId();
	error AlreadyClaimed();
	error AllSlotsClaimed();
	error NotInMerkle();

	constructor(IERC20 _token, address _tokenOwner) Ownable(msg.sender) {
		token = _token;
		tokenOwner = _tokenOwner;
	}

	function createAirdrop(
		string memory partner,
		bool isFcfs,
		uint256 fcfsLimit,
		bytes32 merkleRoot
	) external onlyOwner {
		uint256 id = airdropCount;

		airdrops[id] = PartnerAirdrop({
			id: id,
			partner: partner,
			isFcfs: isFcfs,
			fcfsLimit: fcfsLimit,
			claimedCount: 0,
			merkleRoot: merkleRoot,
			closed: false
		});

		airdropCount += 1;

		emit CreatedAirdrop(id, partner, isFcfs, fcfsLimit, merkleRoot);
	}

	function closeAirdrop(uint256 id, bool closed) external onlyOwner {
		if (id > airdropCount) revert InvalidId();

		airdrops[id].closed = closed;
		emit ClosedAirdrop(id, closed);
	}

	function claim(uint256 id, address user, uint256 amount, bytes32[] calldata proof) external nonReentrant {
		if (id > airdropCount) revert InvalidId();

		if (airdropUserClaimed[id][user]) revert AlreadyClaimed();

		PartnerAirdrop storage airdrop = airdrops[id];
		if (airdrop.isFcfs && airdrop.claimedCount >= airdrop.fcfsLimit) revert AllSlotsClaimed();

		// Verify merkle proof, or revert if not in tree
		bytes32 leaf = keccak256(abi.encodePacked(user, amount));
		bool isValidLeaf = MerkleProof.verify(proof, airdrop.merkleRoot, leaf);
		if (!isValidLeaf) revert NotInMerkle();

		// Mark address to claimed
		airdropUserClaimed[id][user] = true;

		// Increment claimed count
		airdrop.claimedCount += 1;

		// Mint tokens to address
		_transfer(user, amount);

		// Emit claim event
		emit Claimed(id, user, amount);
	}

	function _transfer(address to, uint256 amount) internal {
		token.safeTransferFrom(tokenOwner, to, amount);
	}
}

contract ClaimableAirdropIndividual is Ownable, ReentrancyGuard {
	using SafeERC20 for IERC20;

	IERC20 public token;
	address public tokenOwner;

	string public name;
	bool public closed;

	mapping(address => uint256) public userAmount;
	mapping(address => uint256) public userClaimed;

	event AddedUsers(address[] users, uint256[] amounts);
	event ClosedAirdrop(bool closed);
	event Claimed(address indexed to, uint256 amount);

	error LengthMismatch();
	error Closed();
	error Invalid();
	error NothingToClaim();
	error AlreadyClaimed();

	constructor(IERC20 _token, address _tokenOwner, string memory _name) Ownable(msg.sender) {
		token = _token;
		tokenOwner = _tokenOwner;
		name = _name;
	}

	function addUsers(address[] memory users, uint256[] memory amounts) external onlyOwner {
		if (users.length != amounts.length) revert LengthMismatch();

		for (uint256 i = 0; i < users.length; i++) {
			userAmount[users[i]] += amounts[i];
		}

		emit AddedUsers(users, amounts);
	}

	function closeAirdrop(bool _closed) external onlyOwner {
		closed = _closed;
		emit ClosedAirdrop(closed);
	}

	function claim(address user, uint256 amount) external nonReentrant {
		if (msg.sender != user) revert Invalid();
		if (closed) revert Closed();
		if (userAmount[user] == 0) revert NothingToClaim();

		uint256 claimable = userAmount[user] - userClaimed[user];

		if (claimable == 0) revert AlreadyClaimed();
		if (claimable != amount) revert Invalid();

		userClaimed[user] += claimable;

		_transfer(user, claimable);

		emit Claimed(user, claimable);
	}

	function _transfer(address to, uint256 amount) internal {
		token.safeTransferFrom(tokenOwner, to, amount);
	}

	function getClaimable(address user) public view returns (uint256 claimable) {
		claimable = userAmount[user] - userClaimed[user];
	}
}
