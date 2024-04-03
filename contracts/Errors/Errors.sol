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

/// @dev Error when an individual token TVL is over the max
error MaxTokenTVLReached();

/// @dev Error when Oracle price is invalid
error InvalidOraclePrice();

/// @dev Error when calling an invalid function
error NotImplemented();

/// @dev Error when calculating token amounts is invalid
error InvalidTokenAmount();

/// @dev Error when timestamp is invalid - likely in the past
error InvalidTimestamp(uint256 timestamp);

/// @dev Error when trade does not meet minimum output amount
error InsufficientOutputAmount();

/// @dev Error when the token received over the bridge is not the one expected
error InvalidTokenReceived();

/// @dev Error when the origin address is not whitelisted
error InvalidOrigin();

/// @dev Error when the sender is not expected
error InvalidSender(address expectedSender, address actualSender);

/// @dev error when function returns 0 amount
error InvalidZeroOutput();

/// @dev error when xRenzoBridge does not have enough balance to pay for fee
error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);

/// @dev error when source chain is not expected
error InvalidSourceChain(uint64 expectedCCIPChainSelector, uint64 actualCCIPChainSelector);

/// @dev Error when an unauthorized address tries to call the bridge function on the L2
error UnauthorizedBridgeSweeper();

/// @dev Error when caller does not have BRIDGE_ADMIN role
error NotBridgeAdmin();

/// @dev Error when caller does not have PRICE_FEED_SENDER role
error NotPriceFeedSender();

/// @dev Error for connext price Feed unauthorised call
error UnAuthorisedCall();

/// @dev Error for no price feed configured on L2
error PriceFeedNotAvailable();

/// @dev Error for invalid bridge fee share configuration
error InvalidBridgeFeeShare(uint256 bridgeFee);

/// @dev Error for invalid sweep batch size
error InvalidSweepBatchSize(uint256 batchSize);
