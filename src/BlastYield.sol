// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

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
	// configure
	function configureContract(address contractAddress, YieldMode _yield, GasMode gasMode, address governor) external;
	function configure(YieldMode _yield, GasMode gasMode, address governor) external;

	// base configuration options
	function configureClaimableYield() external;
	function configureClaimableYieldOnBehalf(address contractAddress) external;
	function configureAutomaticYield() external;
	function configureAutomaticYieldOnBehalf(address contractAddress) external;
	function configureVoidYield() external;
	function configureVoidYieldOnBehalf(address contractAddress) external;
	function configureClaimableGas() external;
	function configureClaimableGasOnBehalf(address contractAddress) external;
	function configureVoidGas() external;
	function configureVoidGasOnBehalf(address contractAddress) external;
	function configureGovernor(address _governor) external;
	function configureGovernorOnBehalf(address _newGovernor, address contractAddress) external;

	// claim yield
	function claimYield(address contractAddress, address recipientOfYield, uint amount) external returns (uint);
	function claimAllYield(address contractAddress, address recipientOfYield) external returns (uint);

	// claim gas
	function claimAllGas(address contractAddress, address recipientOfGas) external returns (uint);
	function claimGasAtMinClaimRate(
		address contractAddress,
		address recipientOfGas,
		uint minClaimRateBips
	) external returns (uint);
	function claimMaxGas(address contractAddress, address recipientOfGas) external returns (uint);
	function claimGas(
		address contractAddress,
		address recipientOfGas,
		uint gasToClaim,
		uint gasSecondsToConsume
	) external returns (uint);

	// read functions
	function readClaimableYield(address contractAddress) external view returns (uint);
	function readYieldConfiguration(address contractAddress) external view returns (uint8);
	function readGasParams(
		address contractAddress
	) external view returns (uint etherSeconds, uint etherBalance, uint lastUpdated, GasMode);

	function isGovernor(address contractAddress) external view returns (bool);
	function governorNotSet(address contractAddress) external view returns (bool);
	function isAuthorized(address contractAddress) external view returns (bool);
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
