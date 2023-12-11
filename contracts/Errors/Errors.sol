// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

/// @dev Error for 0x0 address inputs
error InvalidZeroInput();    

/// @dev Error for already added items to a list
error AlreadyAdded();    

/// @dev Error for not found items in a list
error NotFound();    

/// @dev Error for hitting max TVL
error MaxTVLReached();

/// @dev Error for caller not having permissions
error NotRestakeManagerAdmin();

/// @dev Error for call not coming from deposit queue contract
error NotDepositQueue();

/// @dev Error for contract being paused
error ContractPaused(); 

/// @dev Error for exceeding max basis points (100%)
error OverMaxBasisPoints();

/// @dev Error for invalid token decimals for collateral tokens (must be 18)
error InvalidTokenDecimals(uint8 expected, uint8 actual);

/// @dev Error when withdraw is already completed
error WithdrawAlreadyCompleted();

/// @dev Error when a different address tries to complete withdraw
error NotOriginalWithdrawCaller(address expectedCaller);

/// @dev Error when caller does not have OD admin role
error NotOperatorDelegatorAdmin();

/// @dev Error when caller does not have Oracle Admin role
error NotOracleAdmin();

/// @dev Error when caller is not RestakeManager contract
error NotRestakeManager();

/// @dev Errror when caller does not have ETH Restake Admin role
error NotNativeEthRestakeAdmin();

/// @dev Error when delegation address was already set - cannot be set again
error DelegateAddressAlreadySet();

/// @dev Error when caller does not have ERC20 Rewards Admin role
error NotERC20RewardsAdmin();

/// @dev Error when ending ETH fails
error TransferFailed();

/// @dev Error when caller does not have ETH Minter Burner Admin role
error NotEzETHMinterBurner();

/// @dev Error when caller does not have Token Admin role
error NotTokenAdmin();

/// @dev Error when price oracle is not configured
error OracleNotFound();

/// @dev Error when price oracle data is stale
error OraclePriceExpired();

/// @dev Error when array lengths do not match
error MismatchedArrayLengths();

/// @dev Error when caller does not have Deposit Withdraw Pauser role
error NotDepositWithdrawPauser();