// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
pragma experimental ABIEncoderV2;

enum YieldMode {
	AUTOMATIC,
	VOID,
	CLAIMABLE
}

enum GasMode {
	VOID,
	CLAIMABLE
}

interface IBlast {
	function configureClaimableYield() external;
	function claimAllYield(address contractAddress, address recipientOfYield) external returns (uint256);

	function configureClaimableGas() external;
	function claimAllGas(address contractAddress, address recipientOfGas) external returns (uint256);
	function claimGasAtMinClaimRate(
		address contractAddress,
		address recipientOfGas,
		uint256 minClaimRateBips
	) external returns (uint256);
	function claimMaxGas(address contractAddress, address recipientOfGas) external returns (uint256);
	function claimGas(
		address contractAddress,
		address recipientOfGas,
		uint256 gasToClaim,
		uint256 gasSecondsToConsume
	) external returns (uint256);
}

contract BlastYield {
	IBlast public BLAST;

	event ClaimYieldAll(address indexed recipient, uint256 amountETH, uint256 amountGas);

	function _initializeBlast() internal {
		BLAST = IBlast(0x4300000000000000000000000000000000000002);
		BLAST.configureClaimableYield();
		BLAST.configureClaimableGas();
	}

	function _claimYieldAll(address _recipient, uint256 _minClaimRateBips) internal {
		uint256 amountETH = BLAST.claimAllYield(address(this), _recipient);

		uint256 amountGas = _minClaimRateBips == 0
			? BLAST.claimMaxGas(address(this), _recipient)
			: BLAST.claimGasAtMinClaimRate(address(this), _recipient, _minClaimRateBips);

		emit ClaimYieldAll(_recipient, amountETH, amountGas);
	}
}
