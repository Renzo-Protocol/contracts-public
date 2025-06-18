// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IRiskOracle } from "./IRiskOracle.sol";
import { IRiskOracleMiddleware } from "./IRiskOracleMiddleware.sol";
import { RiskOracleMiddlewareStorageV1 } from "./RiskOracleMiddlewareStorage.sol";
import "../../Errors/Errors.sol";

contract RiskOracleMiddleware is
    IRiskOracleMiddleware,
    Initializable,
    RiskOracleMiddlewareStorageV1
{
    // The following constants are used to identify the updateType from Risk Oracle
    string internal constant DEPOSIT_PAUSED = "DEPOSIT_PAUSED";
    string internal constant WITHDRAW_REQUEST_PAUSED = "WITHDRAW_REQUEST_PAUSED";
    string internal constant CLAIM_PAUSED = "CLAIM_PAUSED";
    string internal constant INSTANT_WITHDRAW_PAUSED = "INSTANT_WITHDRAW_PAUSED";
    string internal constant WITHDRAW_COOLDOWN_PERIOD = "WITHDRAW_COOLDOWN_PERIOD";

    // Address of ezETH for market reference
    address internal constant EZETH_ADDRESS = 0xbf5495Efe5DB9ce00f80364C8B423567e58d2110;

    IRiskOracle public immutable riskOracle;

    /// @dev Prevents implementation contract from being initialized.
    /// @param _riskOracle The address of the risk oracle contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IRiskOracle _riskOracle) {
        if (address(_riskOracle) == address(0)) revert InvalidZeroInput();
        riskOracle = _riskOracle;
        _disableInitializers();
    }

    function initialize() public initializer {}

    function depositPaused() external view returns (bool) {
        return isPaused(DEPOSIT_PAUSED);
    }

    function withdrawRequestPaused() external view returns (bool) {
        return isPaused(WITHDRAW_REQUEST_PAUSED);
    }

    function withdrawClaimPaused() external view returns (bool) {
        return isPaused(CLAIM_PAUSED);
    }

    function instantWithdrawPaused() external view returns (bool) {
        return isPaused(INSTANT_WITHDRAW_PAUSED);
    }

    function withdrawCooldownPeriod() external view returns (uint256) {
        uint256 latestParam = getLatestUpdateParam(WITHDRAW_COOLDOWN_PERIOD);
        return latestParam;
    }

    function isPaused(string memory updateType) internal view returns (bool) {
        uint256 latestParam = getLatestUpdateParam(updateType);
        return (latestParam == 1);
    }

    function getLatestUpdateParam(
        string memory updateType
    ) internal view returns (uint256 latestParam) {
        uint256 latestUpdateId = riskOracle.latestUpdateIdByMarketAndType(
            EZETH_ADDRESS,
            updateType
        );
        // check if risk oracle updated at least once
        // if not, returns default values, i.e. no pause or extended cooldown period is required
        if (latestUpdateId > 0) {
            IRiskOracle.RiskParameterUpdate memory latestUpdate = riskOracle.getUpdateById(
                latestUpdateId
            );
            latestParam = abi.decode(latestUpdate.newValue, (uint256));
        }
    }
}
