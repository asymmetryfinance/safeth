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

    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function finalChecks(
        uint256 _amount,
        uint256 _received,
        bool _isDeposit,
        uint256 _underlyingBalance
    ) internal returns (uint256 newUnderlyingBalance) {
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

    receive() external payable {}
}
