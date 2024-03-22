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

interface IERC20Rebasing {
	// changes the yield mode of the caller and update the balance
	// to reflect the configuration
	function configure(YieldMode) external returns (uint256);
	// "claimable" yield mode accounts can call this this claim their yield
	// to another address
	function claim(address recipient, uint256 amount) external returns (uint256);
	// read the claimable amount for an account
	function getClaimableAmount(address account) external view returns (uint256);
}

interface IBlast {
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
	IBlast private _BLAST;
	IERC20Rebasing private _USDB;
	IERC20Rebasing private _WETH;

	event ClaimYieldAll(address indexed recipient, uint256 amountWETH, uint256 amountUSDB, uint256 amountGas);

	function _initializeBlast(address _usdb, address _weth) internal {
		_BLAST = IBlast(0x4300000000000000000000000000000000000002);
		_USDB = IERC20Rebasing(_usdb);
		_WETH = IERC20Rebasing(_weth);

		_BLAST.configureClaimableGas();
		_USDB.configure(YieldMode.CLAIMABLE);
		_WETH.configure(YieldMode.CLAIMABLE);
	}

	function _claimYieldAll(
		address _recipient,
		uint256 _amountWETH,
		uint256 _amountUSDB,
		uint256 _minClaimRateBips
	) internal {
		uint256 amountWETH = _WETH.claim(_recipient, _amountWETH);
		uint256 amountUSDB = _USDB.claim(_recipient, _amountUSDB);
		uint256 amountGas = _minClaimRateBips == 0
			? _BLAST.claimMaxGas(address(this), _recipient)
			: _BLAST.claimGasAtMinClaimRate(address(this), _recipient, _minClaimRateBips);
		emit ClaimYieldAll(_recipient, amountWETH, amountUSDB, amountGas);
	}
}
