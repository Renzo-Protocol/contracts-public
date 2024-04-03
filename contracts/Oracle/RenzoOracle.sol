// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../Permissions/IRoleManager.sol";
import "./RenzoOracleStorage.sol";
import "./IRenzoOracle.sol";
import "../Errors/Errors.sol";

/// @dev This contract will be responsible for looking up values via Chainlink
/// Data retrieved will be verified for liveness via a max age on the oracle lookup.
/// All tokens should be denominated in the same base currency and contain the same decimals on the price lookup.
contract RenzoOracle is
    IRenzoOracle,
    Initializable,
    ReentrancyGuardUpgradeable,
    RenzoOracleStorageV1
{
    /// @dev Error for invalid 0x0 address
    string constant INVALID_0_INPUT = "Invalid 0 input";

    // Scale factor for all values of prices
    uint256 constant SCALE_FACTOR = 10 ** 18;

    /// @dev The maxmimum staleness allowed for a price feed from chainlink
    uint256 constant MAX_TIME_WINDOW = 86400 + 60; // 24 hours + 60 seconds

    /// @dev Allows only a whitelisted address to configure the contract
    modifier onlyOracleAdmin() {
        if (!roleManager.isOracleAdmin(msg.sender)) revert NotOracleAdmin();
        _;
    }

    /// @dev Event emitted when a token's oracle address is updated
    event OracleAddressUpdated(IERC20 token, AggregatorV3Interface oracleAddress);

    /// @dev Prevents implementation contract from being initialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract with initial vars
    function initialize(IRoleManager _roleManager) public initializer {
        if (address(_roleManager) == address(0x0)) revert InvalidZeroInput();

        __ReentrancyGuard_init();

        roleManager = _roleManager;
    }

    /// @dev Sets addresses for oracle lookup.  Permission gated to oracel admins only.
    /// Set to address 0x0 to disable lookups for the token.
    function setOracleAddress(
        IERC20 _token,
        AggregatorV3Interface _oracleAddress
    ) external nonReentrant onlyOracleAdmin {
        if (address(_token) == address(0x0)) revert InvalidZeroInput();

        // Verify that the pricing of the oracle is 18 decimals - pricing calculations will be off otherwise
        if (_oracleAddress.decimals() != 18)
            revert InvalidTokenDecimals(18, _oracleAddress.decimals());

        tokenOracleLookup[_token] = _oracleAddress;
        emit OracleAddressUpdated(_token, _oracleAddress);
    }

    /// @dev Given a single token and balance, return value of the asset in underlying currency
    /// The value returned will be denominated in the decimal precision of the lookup oracle
    /// (e.g. a value of 100 would return as 100 * 10^18)
    function lookupTokenValue(IERC20 _token, uint256 _balance) public view returns (uint256) {
        AggregatorV3Interface oracle = tokenOracleLookup[_token];
        if (address(oracle) == address(0x0)) revert OracleNotFound();

        (, int256 price, , uint256 timestamp, ) = oracle.latestRoundData();
        if (timestamp < block.timestamp - MAX_TIME_WINDOW) revert OraclePriceExpired();
        if (price <= 0) revert InvalidOraclePrice();

        // Price is times 10**18 ensure value amount is scaled
        return (uint256(price) * _balance) / SCALE_FACTOR;
    }

    /// @dev Given a single token and value, return amount of tokens needed to represent that value
    /// Assumes the token value is already denominated in the same decimal precision as the oracle
    function lookupTokenAmountFromValue(
        IERC20 _token,
        uint256 _value
    ) external view returns (uint256) {
        AggregatorV3Interface oracle = tokenOracleLookup[_token];
        if (address(oracle) == address(0x0)) revert OracleNotFound();

        (, int256 price, , uint256 timestamp, ) = oracle.latestRoundData();
        if (timestamp < block.timestamp - MAX_TIME_WINDOW) revert OraclePriceExpired();
        if (price <= 0) revert InvalidOraclePrice();

        // Price is times 10**18 ensure token amount is scaled
        return (_value * SCALE_FACTOR) / uint256(price);
    }

    // @dev Given list of tokens and balances, return total value (assumes all lookups are denomintated in same underlying currency)
    /// The value returned will be denominated in the decimal precision of the lookup oracle
    /// (e.g. a value of 100 would return as 100 * 10^18)
    function lookupTokenValues(
        IERC20[] memory _tokens,
        uint256[] memory _balances
    ) external view returns (uint256) {
        if (_tokens.length != _balances.length) revert MismatchedArrayLengths();

        uint256 totalValue = 0;
        uint256 tokenLength = _tokens.length;
        for (uint256 i = 0; i < tokenLength; ) {
            totalValue += lookupTokenValue(_tokens[i], _balances[i]);
            unchecked {
                ++i;
            }
        }

        return totalValue;
    }

    /// @dev Given amount of current protocol value, new value being added, and supply of ezETH, determine amount to mint
    /// Values should be denominated in the same underlying currency with the same decimal precision
    function calculateMintAmount(
        uint256 _currentValueInProtocol,
        uint256 _newValueAdded,
        uint256 _existingEzETHSupply
    ) external pure returns (uint256) {
        // For first mint, just return the new value added.
        // Checking both current value and existing supply to guard against gaming the initial mint
        if (_currentValueInProtocol == 0 || _existingEzETHSupply == 0) {
            return _newValueAdded; // value is priced in base units, so divide by scale factor
        }

        // Calculate the percentage of value after the deposit
        uint256 inflationPercentaage = (SCALE_FACTOR * _newValueAdded) /
            (_currentValueInProtocol + _newValueAdded);

        // Calculate the new supply
        uint256 newEzETHSupply = (_existingEzETHSupply * SCALE_FACTOR) /
            (SCALE_FACTOR - inflationPercentaage);

        // Subtract the old supply from the new supply to get the amount to mint
        uint256 mintAmount = newEzETHSupply - _existingEzETHSupply;

        // Sanity check
        if (mintAmount == 0) revert InvalidTokenAmount();

        return mintAmount;
    }

    // Given the amount of ezETH to burn, the supply of ezETH, and the total value in the protocol, determine amount of value to return to user
    function calculateRedeemAmount(
        uint256 _ezETHBeingBurned,
        uint256 _existingEzETHSupply,
        uint256 _currentValueInProtocol
    ) external pure returns (uint256) {
        // This is just returning the percentage of TVL that matches the percentage of ezETH being burned
        uint256 redeemAmount = (_currentValueInProtocol * _ezETHBeingBurned) / _existingEzETHSupply;

        // Sanity check
        if (redeemAmount == 0) revert InvalidTokenAmount();

        return redeemAmount;
    }
}
