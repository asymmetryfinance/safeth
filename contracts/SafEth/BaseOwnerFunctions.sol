// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "./Base.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// onlyOwner permissioned functions
contract BaseOwnerFunctions is Base {
    /**
     * @notice sets a recipient address as blacklisted to receive tokens
     * @param _recipient - recipient address to set blacklisted on/off
     * @param _isBlacklisted - true or false
     */
    function setBlacklistedRecipient(
        address _recipient,
        bool _isBlacklisted
    ) external onlyOwner {
        blacklistedRecipients[_recipient] = _isBlacklisted;
    }

    /**
     * @notice sets a sender address as whitelisted to send to blacklisted addressses
     * @param _sender - sender address to set whitelisted on/off
     * @param _isWhitelisted - true or false
     */
    function setWhitelistedSender(
        address _sender,
        bool _isWhitelisted
    ) external onlyOwner {
        whitelistedSenders[_sender] = _isWhitelisted;
    }

    /**
     * @notice sets the eth amount at which it will use standard weighting vs buying a single derivative
     * @param _amount - amount of eth where it will switch to standard weighting
     */
    function setSingleDerivativeThreshold(uint256 _amount) external onlyOwner {
        singleDerivativeThreshold = _amount;
        emit SingleDerivativeThresholdUpdated(_amount);
    }

    /**
        @notice - Claims ETH that was used to acquire preminted safEth
     */
    function withdrawEth() external onlyOwner {
        // solhint-disable-next-line
        (bool sent, ) = address(msg.sender).call{value: ethToClaim}("");
        if (!sent) revert FailedToSend();
        ethToClaim = 0;
    }

    /**
     * @notice - Allows owner to rebalance between 2 derivatives, selling 1 for the other
     * @param _sellDerivativeIndex - index of the derivative to sell
     * @param _buyDerivativeIndex - index of the derivative to buy
     * @param _sellAmount - amount of the derivative to sell
     */
    function derivativeRebalance(
        uint256 _sellDerivativeIndex,
        uint256 _buyDerivativeIndex,
        uint256 _sellAmount
    ) external onlyOwner {
        if (_sellDerivativeIndex >= derivativeCount) revert IndexOutOfBounds();
        if (_buyDerivativeIndex >= derivativeCount) revert IndexOutOfBounds();
        if (_sellDerivativeIndex == _buyDerivativeIndex)
            revert SameDerivative();
        if (_sellAmount == 0) revert AmountTooLow();

        uint256 balanceBefore = address(this).balance;
        derivatives[_sellDerivativeIndex].derivative.withdraw(_sellAmount);
        uint256 balanceAfter = address(this).balance;
        uint256 ethReceived = balanceAfter - balanceBefore;
        derivatives[_buyDerivativeIndex].derivative.deposit{
            value: ethReceived
        }();
    }

    /**
        @notice - Changes Derivative weight based on derivative index
        @dev - Weights are only in regards to each other, total weight changes with this function
        @dev - If you want exact weights either do the math off chain or reset all existing derivates to the weights you want
        @dev - Weights are approximate as it will slowly change as people stake
        @param _derivativeIndex - index of the derivative you want to update the weight
        @param _weight - new weight for this derivative.
    */
    function adjustWeight(
        uint256 _derivativeIndex,
        uint256 _weight
    ) external onlyOwner {
        if (_derivativeIndex >= derivativeCount) revert IndexOutOfBounds();
        if (!derivatives[_derivativeIndex].enabled) revert NotEnabled();

        derivatives[_derivativeIndex].weight = _weight;
        setTotalWeight();
        emit WeightChange(_derivativeIndex, _weight, totalWeight);
    }

    /**
        @notice - Disables Derivative based on derivative index
        @param _derivativeIndex - index of the derivative you want to disable
    */
    function disableDerivative(uint256 _derivativeIndex) external onlyOwner {
        if (_derivativeIndex >= derivativeCount) revert IndexOutOfBounds();
        if (!derivatives[_derivativeIndex].enabled) revert NotEnabled();

        derivatives[_derivativeIndex].enabled = false;
        setTotalWeight();
        emit DerivativeDisabled(_derivativeIndex);
    }

    /**
        @notice - Enables Derivative based on derivative index
        @param _derivativeIndex - index of the derivative you want to enable
    */
    function enableDerivative(uint256 _derivativeIndex) external onlyOwner {
        if (_derivativeIndex >= derivativeCount) revert IndexOutOfBounds();
        if (derivatives[_derivativeIndex].enabled) revert AlreadyEnabled();

        derivatives[_derivativeIndex].enabled = true;
        setTotalWeight();
        emit DerivativeEnabled(_derivativeIndex);
    }

    /**
        @notice - Adds new derivative to the index fund
        @param _contractAddress - Address of the derivative contract launched by AF
        @param _weight - new weight for this derivative. 
    */
    function addDerivative(
        address _contractAddress,
        uint256 _weight
    ) external onlyOwner {
        try
            ERC165(_contractAddress).supportsInterface(
                type(IDerivative).interfaceId
            )
        returns (bool supported) {
            // Contract supports ERC-165 but invalid
            if (!supported) revert InvalidDerivative();
        } catch {
            // Contract doesn't support ERC-165
            revert InvalidDerivative();
        }

        derivatives[derivativeCount].derivative = IDerivative(_contractAddress);
        derivatives[derivativeCount].weight = _weight;
        derivatives[derivativeCount].enabled = true;
        emit DerivativeAdded(_contractAddress, _weight, derivativeCount);
        unchecked {
            ++derivativeCount;
        }
        setTotalWeight();
    }

    /**
     * @notice - Sets total weight of all enabled derivatives
     */
    function setTotalWeight() private {
        uint256 localTotalWeight = 0;
        uint256 count = derivativeCount;

        for (uint256 i = 0; i < count; i++) {
            if (!derivatives[i].enabled || derivatives[i].weight == 0) continue;
            localTotalWeight += derivatives[i].weight;
        }
        totalWeight = localTotalWeight;
    }

    /**
        @notice - Sets the max slippage for a certain derivative index
        @param _derivativeIndex - index of the derivative you want to update the slippage
        @param _slippage - new slippage amount in wei
    */
    function setMaxSlippage(
        uint256 _derivativeIndex,
        uint256 _slippage
    ) external onlyOwner {
        if (_derivativeIndex >= derivativeCount) revert IndexOutOfBounds();

        derivatives[_derivativeIndex].derivative.setMaxSlippage(_slippage);
        emit SetMaxSlippage(_derivativeIndex, _slippage);
    }

    /**
        @notice - Sets the minimum amount a user is allowed to stake
        @param _minAmount - amount to set as minimum stake value
    */
    function setMinAmount(uint256 _minAmount) external onlyOwner {
        emit ChangeMinAmount(minAmount, _minAmount);
        minAmount = _minAmount;
    }

    /**
        @notice - Owner only function that sets the maximum amount a user is allowed to stake
        @param _maxAmount - amount to set as maximum stake value
    */
    function setMaxAmount(uint256 _maxAmount) external onlyOwner {
        emit ChangeMaxAmount(maxAmount, _maxAmount);
        maxAmount = _maxAmount;
    }

    /**
        @notice - Owner only function that Enables/Disables the stake function
        @param _pause - true disables staking / false enables staking
    */
    function setPauseStaking(bool _pause) external onlyOwner {
        if (pauseStaking == _pause) revert AlreadySet();
        pauseStaking = _pause;
        emit StakingPaused(_pause);
    }

    /**
        @notice - Sets the maximum amount a user can premint in one transaction
        @param _amount - amount to set as maximum premint value
        @dev - This is to prevent a whale from coming in and taking all the preminted funds
        @dev - A user can stake multiple times and still receive the preminted funds
    */
    function setMaxPreMintAmount(uint256 _amount) external onlyOwner {
        maxPreMintAmount = _amount;
        emit MaxPreMintAmount(_amount);
    }

    /**
        @notice - Owner only function that enables/disables the unstake function
        @param _pause - true disables unstaking / false enables unstaking
    */
    function setPauseUnstaking(bool _pause) external onlyOwner {
        if (pauseUnstaking == _pause) revert AlreadySet();
        pauseUnstaking = _pause;
        emit UnstakingPaused(_pause);
    }

    function setChainlinkFeed(
        uint256 derivativeIndex,
        address feed
    ) external onlyOwner {
        derivatives[derivativeIndex].derivative.setChainlinkFeed(feed);
    }
}
