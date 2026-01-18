# Renzo Protocol Test Suite

This directory contains comprehensive test coverage for the Renzo Protocol smart contracts.

## Test Structure

```
test/
├── RoleManager.test.ts        # Tests for RoleManager access control
├── EzEthToken.test.ts         # Tests for ezETH token functionality
├── RenzoOracle.test.ts        # Tests for oracle price feeds
├── DepositQueue.test.ts       # Tests for deposit queue operations
├── STETHShim.test.ts          # Tests for stETH Chainlink shim
├── BalancerRateProvider.test.ts # Tests for Balancer rate provider
├── mocks/                     # Mock contracts for testing
│   ├── MockChainlinkOracle.sol
│   ├── MockERC20.sol
│   ├── MockRestakeManager.sol
│   └── MockWithdrawQueue.sol
└── helpers/
    └── testSetup.ts           # Shared test utilities and fixtures
```

## Running Tests

```bash
# Install dependencies
npm install

# Compile contracts
npm run compile

# Run all tests
npm test

# Run specific test file
npx hardhat test test/RoleManager.test.ts

# Run tests with gas reporting
REPORT_GAS=true npm test

# Run tests with coverage
npx hardhat coverage
```

## Test Coverage

The test suite covers the following contracts and functionalities:

### RoleManager
- Initialization and admin setup
- Role granting and revocation
- Role checking functions (isRxEthMinterBurner, isOracleAdmin, etc.)
- Multiple roles per user
- Role renunciation
- Admin role transfer

### EzEthToken
- Token metadata (name, symbol, decimals)
- Minting (authorized minter only)
- Burning (authorized burner only)
- Transfers between users
- Allowances and approvals
- Role-based access control integration

### RenzoOracle
- Oracle configuration
- Token price lookups
- Stale data handling
- Invalid price handling
- Mint amount calculations
- Redeem amount calculations

### DepositQueue
- Fee configuration
- RestakeManager integration
- WithdrawQueue integration
- ETH deposit handling
- Role-based access control

### STETHShim
- Chainlink interface compliance
- 1:1 price ratio for stETH:ETH
- Metadata functions

### BalancerRateProvider
- Rate calculations with various TVL/supply ratios
- Edge cases (zero supply, large numbers)
- IRateProvider interface compliance

## Mock Contracts

Mock contracts are provided in `test/mocks/` for isolated unit testing:

- **MockChainlinkOracle**: Simulates Chainlink price feeds with configurable prices and staleness
- **MockERC20**: Standard ERC20 with mint/burn for testing
- **MockRestakeManager**: Simulates RestakeManager for deposit/withdrawal testing
- **MockWithdrawQueue**: Simulates WithdrawQueue for claim testing

## Test Helpers

`test/helpers/testSetup.ts` provides:

- Role hash constants
- Common test constants
- Contract deployment helpers
- Full fixture deployment
- Time manipulation utilities
- Snapshot/revert utilities

## Best Practices

1. **Isolation**: Each test is isolated using `beforeEach` hooks
2. **Comprehensive**: Tests cover happy paths, edge cases, and error conditions
3. **Readable**: Descriptive test names and organized `describe` blocks
4. **Maintainable**: Shared fixtures and utilities reduce code duplication

## Adding New Tests

1. Create a new test file in `test/` directory
2. Import necessary helpers from `test/helpers/testSetup.ts`
3. Follow existing test patterns for consistency
4. Add any new mock contracts to `test/mocks/`

## Contributing

When adding tests:
- Ensure 100% line coverage for new contracts
- Test all public and external functions
- Include both success and failure cases
- Test edge cases and boundary conditions
- Update this README with new test coverage
