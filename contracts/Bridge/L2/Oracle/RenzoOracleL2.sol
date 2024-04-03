// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./RenzoOracleL2Storage.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../../../Errors/Errors.sol";

contract RenzoOracleL2 is Initializable, OwnableUpgradeable, RenzoOracleL2StorageV1 {
    /// @dev The maxmimum staleness allowed for a price feed from chainlink
    uint256 public constant MAX_TIME_WINDOW = 86400 + 60; // 24 hours + 60 seconds

    event OracleAddressUpdated(address newOracle, address oldOracle);

    /// @dev Prevents implementation contract from being initialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(AggregatorV3Interface _oracle) public initializer {
        // Initialize inherited classes
        __Ownable_init();

        if (address(_oracle) == address(0)) revert InvalidZeroInput();

        // Verify that the pricing of the oracle less than or equal 18 decimals - pricing calculations will be off otherwise
        if (_oracle.decimals() > 18) revert InvalidTokenDecimals(18, _oracle.decimals());

        oracle = _oracle;
    }

    /// @dev Sets addresses for oracle lookup.  Permission gated to owner only.
    function setOracleAddress(AggregatorV3Interface _oracleAddress) external onlyOwner {
        if (address(_oracleAddress) == address(0)) revert InvalidZeroInput();
        // Verify that the pricing of the oracle is less than or equal to 18 decimals - pricing calculations will be off otherwise
        if (_oracleAddress.decimals() > 18)
            revert InvalidTokenDecimals(18, _oracleAddress.decimals());

        emit OracleAddressUpdated(address(_oracleAddress), address(oracle));
        oracle = _oracleAddress;
    }

    /**
     * @notice Pulls the price of ezETH
     * @dev reverts if price is less than 1 Ether
     */
    function getMintRate() public view returns (uint256, uint256) {
        (, int256 price, , uint256 timestamp, ) = oracle.latestRoundData();
        if (timestamp < block.timestamp - MAX_TIME_WINDOW) revert OraclePriceExpired();
        // scale the price to have 18 decimals
        uint256 _scaledPrice = (uint256(price)) * 10 ** (18 - oracle.decimals());
        if (_scaledPrice < 1 ether) revert InvalidOraclePrice();
        return (_scaledPrice, timestamp);
    }
}
