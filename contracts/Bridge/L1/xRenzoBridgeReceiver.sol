// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import "./xRenzoBridgeReceiverStorage.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../../Errors/Errors.sol";
import "../Connext/core/IWeth.sol";
import "../xERC20/interfaces/IXERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./IwstETH.sol";

contract xRenzoBridgeReceiver is
    Initializable,
    ReentrancyGuardUpgradeable,
    xRenzoBridgeReceiverStorageV1
{
    using SafeERC20 for IERC20;

    /// @dev Event emitted when bridged funds are processed
    event EzETHProcessed(uint256 ezETHMinted, uint256 xezETHBurned);

    modifier onlyBridgeAdmin() {
        if (!roleManager.isBridgeAdmin(msg.sender)) revert NotBridgeAdmin();
        _;
    }

    /// @dev Prevents implementation contract from being initialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract with initial vars
    function initialize(
        IERC20 _ezETH,
        IERC20 _xezETH,
        IERC20 _wETH,
        IERC20 _stETH,
        IERC20 _wstETH,
        IRestakeManager _restakeManager,
        IRoleManager _roleManager,
        IXERC20Lockbox _xezETHLockbox
    ) public initializer {
        // Verify non-zero addresses on inputs
        if (
            address(_ezETH) == address(0) ||
            address(_xezETH) == address(0) ||
            address(_restakeManager) == address(0) ||
            address(_wETH) == address(0) ||
            address(_stETH) == address(0) ||
            address(_wstETH) == address(0) ||
            address(_xezETHLockbox) == address(0) ||
            address(_roleManager) == address(0)
        ) {
            revert InvalidZeroInput();
        }

        __ReentrancyGuard_init();

        // Save off inputs
        ezETH = _ezETH;
        xezETH = _xezETH;
        restakeManager = _restakeManager;
        wETH = _wETH;
        wstETH = _wstETH;
        stETH = _stETH;
        xezETHLockbox = _xezETHLockbox;
        roleManager = _roleManager;
    }

    /**
     * @notice  Processes any funds sent into the contract and deposits into the protocol
     * @dev     This function will take all collateral and deposit it into Renzo
     *          The ezETH from the deposit will be sent to the lockbox to be wrapped into xezETH
     *          The xezETH will be burned so that the xezETH on the L2 can be unwrapped for ezETH later
     * @notice  WARNING: This function does NOT whitelist who can send funds from the L2.  Users should NOT
     *          send funds directly to this contract.  A user who sends funds directly to this contract will cause
     *          the tokens on the L2 to become over collateralized and will be a "donation" to protocol.  Only use
     *          the deposit contracts on the L2 to send funds to this contract.
     */
    function processDeposits() external nonReentrant returns (uint256) {
        // Process any WETH - Just unwrap it and handle ETH below
        if (wETH.balanceOf(address(this)) > 0) {
            // Unwrap the WETH
            IWeth(address(wETH)).withdraw(wETH.balanceOf(address(this)));
        }

        // Process any ETH
        if (address(this).balance > 0) {
            // Get the amount of ETH
            uint256 ethAmount = address(this).balance;

            // Deposit it into Renzo RestakeManager
            restakeManager.depositETH{ value: ethAmount }();
        }

        // Process any wstETH - unwrap and deposit stETH
        if (wstETH.balanceOf(address(this)) > 0) {
            IwstETH(address(wstETH)).unwrap(wstETH.balanceOf(address(this)));

            uint256 stETHAmount = stETH.balanceOf(address(this));

            // Check that the amount received is greater than 0
            if (stETHAmount == 0) {
                revert InvalidZeroInput();
            }

            // Approve and deposit it into Renzo RestakeManager
            stETH.safeIncreaseAllowance(address(restakeManager), stETHAmount);
            restakeManager.deposit(stETH, stETHAmount);
        }

        // Get the amount of ezETH that was minted
        uint256 ezETHAmount = ezETH.balanceOf(address(this));

        // Check that the amount of ezETH is greater than 0
        if (ezETHAmount == 0) {
            revert InvalidZeroInput();
        }

        // Approve the lockbox to spend the ezETH
        ezETH.safeIncreaseAllowance(address(xezETHLockbox), ezETHAmount);

        // Send to the lockbox to be wrapped into xezETH
        xezETHLockbox.deposit(ezETHAmount);

        // Get the amount of xezETH that was minted
        uint256 xezETHAmount = xezETH.balanceOf(address(this));

        // Burn it - it was already minted on the L2
        IXERC20(address(xezETH)).burn(address(this), xezETHAmount);

        // Emit the event
        emit EzETHProcessed(ezETHAmount, xezETHAmount);

        // Return amount processed
        return xezETHAmount;
    }

    /**
     * @notice  Sweeps accidental ERC20 value sent to the contract
     * @dev     Restricted to be called by the bridge admin only.
     * @param   _token  address of the ERC20 token
     * @param   _amount  amount of ERC20 token
     * @param   _to  destination address
     */
    function recoverERC20(address _token, uint256 _amount, address _to) external onlyBridgeAdmin {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /**
     * @notice Fallback function to handle ETH sent to the contract from unwrapping WETH
     * @dev Warning: users should not send ETH directly to this contract!
     */
    receive() external payable {}
}
