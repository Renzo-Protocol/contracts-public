//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "../EigenLayer/interfaces/IStrategy.sol";
import "./TestingStrategy.sol";
import "../EigenLayer/interfaces/IStrategyManager.sol";

/// @dev this is just a contract to use in unit testing - allows setting return values and mimics minimal logic
contract TestingStrategyManager {
    uint256 public depositIntoStrategyReturnValue;
    mapping(address => IStrategy[]) public stakerStrategyList;

    function setDepositIntoStrategyReturnValue(uint256 _returnValue) external {
        depositIntoStrategyReturnValue = _returnValue;
    }

    function stakerStrategyListLength(
        address _staker
    ) external view returns (uint256) {
        return stakerStrategyList[_staker].length;
    }

    ///
    function depositIntoStrategy(
        IStrategy strategy,
        IERC20 token,
        uint256 amount
    ) external returns (uint256 shares) {
        // Transfer tokens into this strategy
        token.transferFrom(msg.sender, address(strategy), amount);

        // Calculate the number of tokens and shares
        TestingStrategy testingStrategy = TestingStrategy(address(strategy));
        uint256 existingTokens = testingStrategy.underlyingTokens();
        uint256 existingShares = testingStrategy.shares();

        // If either is 0, just add them both as the value
        if (existingShares == 0 || existingTokens == 0) {
            testingStrategy.setUnderlyingTokens(amount);
            testingStrategy.setShares(amount);
        } else {
            testingStrategy.setUnderlyingTokens(existingTokens + amount);
            testingStrategy.setShares(
                existingShares + (amount * existingShares) / existingTokens
            );
        }

        // Get the number of tokens for the account
        uint256 accountTokens = testingStrategy.accountTokens(msg.sender);

        // Update it with the new amount
        testingStrategy.setAccountTokens(msg.sender, accountTokens + amount);

        // Add the strategy to the staker if it doesn't exist
        bool found = false;
        for (uint8 i = 0; i < stakerStrategyList[msg.sender].length; i++) {
            if (stakerStrategyList[msg.sender][i] == strategy) {
                found = true;
                break;
            }
        }

        // Add it if not found
        if (!found) {
            stakerStrategyList[msg.sender].push(strategy);
        }

        return depositIntoStrategyReturnValue;
    }

    function calculateWithdrawalRoot(IStrategyManager.QueuedWithdrawal memory queuedWithdrawal) public pure returns (bytes32) {
        return (
            keccak256(
                abi.encode(
                    queuedWithdrawal.strategies,
                    queuedWithdrawal.shares,
                    queuedWithdrawal.depositor,
                    queuedWithdrawal.withdrawerAndNonce,
                    queuedWithdrawal.withdrawalStartBlock,
                    queuedWithdrawal.delegatedAddress
                )
            )
        );
    }

    uint256 constant withdrawBlockWait = 100;
    mapping(bytes32 => IStrategyManager.QueuedWithdrawal) public pendingWithdrawals;
    mapping(address => uint256) public numWithdrawalsQueued;
    mapping(address => mapping(IStrategy => uint256)) public stakerStrategyShares;
    IStrategy public constant beaconChainETHStrategy = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0);

    function setStakeryStrategyShares(address staker, uint256 shares) external {
        stakerStrategyShares[staker][beaconChainETHStrategy] = shares;
    }

    function queueWithdrawal(
        uint256[] calldata,
        IStrategy[] calldata strategies,
        uint256[] calldata shares,
        address withdrawer,
        bool
    )
        external returns(bytes32){
          require(shares.length == strategies.length, "invalid array lengths");
          require(shares.length == 1, "only supports 1 strategy");

          TestingStrategy testingStrategy = TestingStrategy(address(strategies[0]));

          // Get the number of underlying from shares
          uint256 underlyingTokens = testingStrategy.sharesToUnderlyingView(shares[0]);

          // Get the accounts token amount
          uint256 existingTokenBalance = testingStrategy.accountTokens(msg.sender);
          require(existingTokenBalance >= underlyingTokens, "insufficient tokens");

         IStrategyManager.WithdrawerAndNonce memory withdrawerAndNonce = IStrategyManager.WithdrawerAndNonce({
                withdrawer: withdrawer,
                nonce: uint96(numWithdrawalsQueued[withdrawer])
            });
          
          numWithdrawalsQueued[withdrawer] = numWithdrawalsQueued[withdrawer] + 1;

          // Get the queued withdrawal object
          IStrategyManager.QueuedWithdrawal memory queuedWithdrawal = IStrategyManager.QueuedWithdrawal({
                strategies: strategies,
                shares: shares,
                depositor: msg.sender,
                withdrawerAndNonce: withdrawerAndNonce,
                withdrawalStartBlock: uint32(block.number),
                delegatedAddress: address(0x0) // TODO: handle delegations
            });

          // Calculate the hash
          bytes32 withdrawalRoot = calculateWithdrawalRoot(queuedWithdrawal);

          // Set the queued withdrawal
          pendingWithdrawals[withdrawalRoot] = queuedWithdrawal;

          return withdrawalRoot;
        }
    
    function completeQueuedWithdrawal(
        IStrategyManager.QueuedWithdrawal calldata queuedWithdrawal,
        IERC20[] calldata tokens,
        uint256,
        bool
    )
        external{          
          // Calculate the withdrawalRoot
          bytes32 withdrawalRoot = calculateWithdrawalRoot(queuedWithdrawal);

          // Verify it exists
          require(pendingWithdrawals[withdrawalRoot].withdrawalStartBlock != 0, "withdrawal not queued");

          // Verify the block wait has passed
          require(block.number >= pendingWithdrawals[withdrawalRoot].withdrawalStartBlock + withdrawBlockWait, "block wait not passed");

          // Get the strategy
          TestingStrategy strategy = TestingStrategy(address(pendingWithdrawals[withdrawalRoot].strategies[0])); 

          // Get the current underlying tokens
          uint256 underlyingTokens = strategy.underlyingTokens();

          // Get the current shares
          uint256 shares = strategy.shares();

          // Get the token amount from strategy
          uint256 underlyingTokensToWithdraw = strategy.sharesToUnderlyingView(pendingWithdrawals[withdrawalRoot].shares[0]);

          // Pull the tokens from the strategy
          strategy.withdrawTokens(tokens[0], queuedWithdrawal.withdrawerAndNonce.withdrawer, underlyingTokensToWithdraw);

          // Set the updated tokens
          strategy.setUnderlyingTokens(underlyingTokens - underlyingTokensToWithdraw);
          
          // Set the updated shares
          strategy.setShares(shares - pendingWithdrawals[withdrawalRoot].shares[0]);
        }
}
