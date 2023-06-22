// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/introspection/ERC165Storage.sol";
import "../../interfaces/IDerivative.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract DerivativeBase is
    ERC165Storage,
    IDerivative,
    Initializable,
    OwnableUpgradeable
{
    error SlippageTooHigh();
    error FailedToSend();
    error InvalidAddress();
    error AlreadyInitialized();
    error Unauthorized();

    event ManagerUpdated(address _manager);

    address public manager;

    modifier onlyManager() {
        if (msg.sender != manager) revert Unauthorized();
        _;
    }

    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
        @notice - Sets the manager address for the derivative
    */
    function initializeV2() external {
        if (manager != address(0)) revert AlreadyInitialized();
        manager = 0x263b03BbA0BbbC320928B6026f5eAAFAD9F1ddeb;
    }

    function finalChecks(
        uint256 _price,
        uint256 _amount,
        uint256 _maxSlippage,
        uint256 _received,
        bool _isDeposit,
        uint256 _underlyingBalance
    ) internal returns (uint256 newUnderlyingBalance) {
        uint256 minOut = _isDeposit
            ? ((_amount * (1e18 - _maxSlippage)) / _price)
            : (((_price * _amount) * (1e18 - _maxSlippage)) / 1e36);
        if (_received < minOut) revert SlippageTooHigh();
        if (!_isDeposit) {
            // solhint-disable-next-line
            (bool sent, ) = address(msg.sender).call{value: _received}("");
            if (!sent) revert FailedToSend();
            return _underlyingBalance - _amount;
        }
        return _underlyingBalance + _received;
    }

    function init(address _owner) internal {
        if (_owner == address(0)) revert InvalidAddress();
        _registerInterface(type(IDerivative).interfaceId);
        _transferOwnership(_owner);
    }

    function updateManager(address _manager) external onlyManager {
        if (_manager == address(0)) revert InvalidAddress();
        manager = _manager;
        emit ManagerUpdated(_manager);
    }

    receive() external payable {}
}
