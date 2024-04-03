// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./EigenLayer/interfaces/IStrategy.sol";
import "./EigenLayer/interfaces/IDelegationManager.sol";
import "./EigenLayer/interfaces/IStrategyManager.sol";
import "./token/IEzEthToken.sol";
import "./Delegation/IOperatorDelegator.sol";
import "./Permissions/IRoleManager.sol";
import "./Oracle/IRenzoOracle.sol";
import "./Deposits/IDepositQueue.sol";
import "./IRestakeManager.sol";

abstract contract RestakeManagerStorageV1 is IRestakeManager {
    /// @dev reference to the RoleManager contract
    IRoleManager public roleManager;

    /// @dev reference to the ezETH token contract
    IEzEthToken public ezETH;

    /// @dev reference to the strategyManager contract in EigenLayer
    IStrategyManager public strategyManager;

    /// @dev reference to the delegationManager contract in EigenLayer
    IDelegationManager public delegationManager;

    /// @dev data stored for a withdrawal
    struct PendingWithdrawal {
        uint256 ezETHToBurn;
        address withdrawer;
        IERC20 tokenToWithdraw;
        uint256 tokenAmountToWithdraw;
        IOperatorDelegator operatorDelegator;
        bool completed;
    }

    /// @dev mapping of pending withdrawals, indexed by the withdrawal root from EigenLayer
    mapping(bytes32 => PendingWithdrawal) public pendingWithdrawals;

    /// @dev Stores the list of OperatorDelegators
    IOperatorDelegator[] public operatorDelegators;

    /// @dev Mapping to store the allocations to each operatorDelegator
    /// Stored in basis points (e.g. 1% = 100)
    mapping(IOperatorDelegator => uint256) public operatorDelegatorAllocations;

    /// @dev Stores the list of collateral tokens
    IERC20[] public collateralTokens;

    /// @dev Reference to the oracle contract
    IRenzoOracle public renzoOracle;

    /// @dev Controls pause state of contract
    bool public paused;

    /// @dev The max amount of TVL allowed.  If this is set to 0, no max TVL is enforced
    uint256 public maxDepositTVL;

    /// @dev Reference to the deposit queue contract
    IDepositQueue public depositQueue;
}

abstract contract RestakeManagerStorageV2 is RestakeManagerStorageV1 {
    mapping(IERC20 => uint256) public collateralTokenTvlLimits;
}
