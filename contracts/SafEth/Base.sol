// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "./SafEthStorage.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// constructor/initializer, overrides
contract Base is
    Initializable,
    ERC20Upgradeable,
    Ownable2StepUpgradeable,
    SafEthStorage,
    ReentrancyGuardUpgradeable
{
    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
        @notice - Function to initialize values for the contracts
        @dev - This replaces the constructor for upgradeable contracts
        @param _tokenName - name of erc20
        @param _tokenSymbol - symbol of erc20
    */
    function initialize(
        string memory _tokenName,
        string memory _tokenSymbol
    ) external initializer {
        ERC20Upgradeable.__ERC20_init(_tokenName, _tokenSymbol);
        Ownable2StepUpgradeable.__Ownable2Step_init();
        minAmount = 5 * 1e16; // initializing with .05 ETH as minimum
        maxAmount = 200 * 1e18; // initializing with 200 ETH as maximum
        pauseStaking = true; // pause staking on initialize for adding derivatives
        __ReentrancyGuard_init();
        singleDerivativeThreshold = 10e18;
    }

    /**
     * @notice - standard erc20 transferFrom() with checkBlacklist modifier
     * @param sender - sender address
     * @param recipient - recipient address
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        if (blacklistedRecipients[recipient] && !whitelistedSenders[sender])
            revert BlacklistedAddress();
        return super.transferFrom(sender, recipient, amount);
    }

    /**
     * @notice - standard erc20 transfer() with checkBlacklist modifier
     * @param _recipient - _recipient address
     * @param _amount = _amount to transfer
     */
    function transfer(
        address _recipient,
        uint256 _amount
    ) public override returns (bool) {
        if (
            blacklistedRecipients[_recipient] && !whitelistedSenders[msg.sender]
        ) revert BlacklistedAddress();
        return super.transfer(_recipient, _amount);
    }
}
