// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "./SafEthStorage.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./BaseOwnerFunctions.sol";

/// @title Contract that mints/burns and provides owner functions for safETH
/// @author Asymmetry Finance

contract SafEth is BaseOwnerFunctions {
    /**
        @notice - Stake your ETH into safETH
        @dev - Deposits into each derivative based on its weight
        @dev - Mints safEth in a redeemable value which equals to the correct percentage of the total staked value
        @param _minOut - Minimum amount of safETH to mint
        @return mintedAmount - Amount of safETH minted
    */
    function stake(
        uint256 _minOut
    )
        external
        payable
        nonReentrant
        returns (uint256 mintedAmount, uint256 depositPrice)
    {
        if (pauseStaking) revert StakingPausedError();
        if (msg.value < minAmount) revert AmountTooLow();
        if (msg.value > maxAmount) revert AmountTooHigh();
        if (totalWeight == 0) revert TotalWeightZero();

        depositPrice = approxPrice(true);

        uint256 preMintPrice = depositPrice < floorPrice
            ? floorPrice
            : depositPrice;
        uint256 amountFromPreMint = (msg.value * 1e18) / preMintPrice;
        if (
            amountFromPreMint <= preMintedSupply &&
            msg.value <= maxPreMintAmount
        ) {
            if (amountFromPreMint < _minOut) revert PremintTooLow();

            // Use preminted safeth
            ethToClaim += msg.value;
            depositPrice = preMintPrice;
            preMintedSupply -= amountFromPreMint;
            IERC20(address(this)).transfer(msg.sender, amountFromPreMint);
            emit Staked(
                msg.sender,
                msg.value,
                (amountFromPreMint * depositPrice) / 1e18,
                depositPrice,
                true
            );
        } else {
            // Mint new safeth
            uint256 totalStakeValueEth = 0; // Total amount of derivatives staked by user in eth
            uint256 amountStaked = 0;

            // deposits less than singleDerivativeThreshold go into the first underweight derivative (saves gas)
            if (msg.value < singleDerivativeThreshold) {
                IDerivative derivative = derivatives[
                    firstUnderweightDerivativeIndex()
                ].derivative;
                uint256 depositAmount = derivative.deposit{value: msg.value}();
                uint256 derivativeReceivedEthValue = (derivative
                    .ethPerDerivative(true) * depositAmount);
                totalStakeValueEth += derivativeReceivedEthValue;
            }
            // otherwise deposit according to weights
            else {
                for (uint256 i = 0; i < derivativeCount; i++) {
                    if (!derivatives[i].enabled) continue;
                    uint256 weight = derivatives[i].weight;
                    if (weight == 0) continue;
                    IDerivative derivative = derivatives[i].derivative;
                    uint256 ethAmount = i == derivativeCount - 1
                        ? msg.value - amountStaked
                        : (msg.value * weight) / totalWeight;

                    amountStaked += ethAmount;
                    uint256 depositAmount = derivative.deposit{
                        value: ethAmount
                    }();
                    // This is slightly less than ethAmount because slippage
                    uint256 derivativeReceivedEthValue = (derivative
                        .ethPerDerivative(true) * depositAmount);
                    totalStakeValueEth += derivativeReceivedEthValue;
                }
            }
            // MintedAmount represents a percentage of the total assets in the system
            mintedAmount = (totalStakeValueEth) / depositPrice;
            if (mintedAmount < _minOut) revert MintedAmountTooLow();

            _mint(msg.sender, mintedAmount);
            emit Staked(
                msg.sender,
                msg.value,
                totalStakeValueEth / 1e18,
                depositPrice,
                false
            );
        }
    }

    /**
        @notice - Unstake your safETH into ETH
        @dev - Unstakes a percentage of safEth based on its total value
        @param _safEthAmount - Amount of safETH to unstake into ETH
        @param _minOut - Minimum amount of ETH to unstake
    */
    function unstake(
        uint256 _safEthAmount,
        uint256 _minOut
    ) external nonReentrant {
        if (pauseUnstaking) revert UnstakingPausedError();
        if (_safEthAmount == 0) revert AmountTooLow();
        if (_safEthAmount > balanceOf(msg.sender)) revert InsufficientBalance();

        uint256 safEthTotalSupply = totalSupply();
        uint256 ethAmountBefore = address(this).balance;
        uint256 count = derivativeCount;

        for (uint256 i = 0; i < count; i++) {
            if (!derivatives[i].enabled) continue;
            // withdraw a percentage of each asset based on the amount of safETH
            uint256 derivativeAmount = (derivatives[i].derivative.balance() *
                _safEthAmount) / safEthTotalSupply;
            if (derivativeAmount == 0) continue; // if derivative empty ignore
            // Add check for a zero Ether received
            uint256 ethBefore = address(this).balance;
            derivatives[i].derivative.withdraw(derivativeAmount);
            if (address(this).balance - ethBefore == 0)
                revert ReceivedZeroAmount();
        }
        _burn(msg.sender, _safEthAmount);
        uint256 ethAmountAfter = address(this).balance;
        uint256 ethAmountToWithdraw = ethAmountAfter - ethAmountBefore;
        if (ethAmountToWithdraw < _minOut) revert AmountTooLow();

        // solhint-disable-next-line
        (bool sent, ) = address(msg.sender).call{value: ethAmountToWithdraw}(
            ""
        );
        if (!sent) revert FailedToSend();
        emit Unstaked(
            msg.sender,
            ethAmountToWithdraw,
            _safEthAmount,
            approxPrice(true)
        );
    }

    /**
        @notice - Premints safEth for future users
        @param _minAmount - minimum amount to stake
        @param _useBalance - should use balance from previous premint's to mint more
     */
    function preMint(
        uint256 _minAmount,
        bool _useBalance
    ) external payable onlyOwner returns (uint256) {
        uint256 amount = msg.value;
        if (_useBalance) {
            amount += ethToClaim;
            ethToClaim = 0;
        }
        (uint256 mintedAmount, uint256 depositPrice) = this.stake{
            value: amount
        }(_minAmount);

        floorPrice = depositPrice;
        preMintedSupply += mintedAmount;
        emit PreMint(amount, mintedAmount, depositPrice);
        return mintedAmount;
    }

    /**
     * @notice - Get the approx price of safEth.
     * @dev - This is approximate because of slippage when acquiring / selling the underlying
     * @return - Approximate price of safEth in wei
     */
    function approxPrice(bool _validate) public view returns (uint256) {
        uint256 safEthTotalSupply = totalSupply();
        uint256 underlyingValue = 0;
        uint256 count = derivativeCount;

        for (uint256 i = 0; i < count; i++) {
            if (!derivatives[i].enabled) continue;
            IDerivative derivative = derivatives[i].derivative;
            underlyingValue += (derivative.ethPerDerivative(_validate) *
                derivative.balance());
        }
        if (safEthTotalSupply == 0 || underlyingValue == 0) return 1e18;
        return (underlyingValue) / safEthTotalSupply;
    }

    function firstUnderweightDerivativeIndex() private view returns (uint256) {
        uint256 count = derivativeCount;

        uint256 tvlEth = totalSupply() * approxPrice(false);

        if (tvlEth == 0) return 0;

        for (uint256 i = 0; i < count; i++) {
            if (!derivatives[i].enabled) continue;
            uint256 trueWeight = (totalWeight *
                IDerivative(derivatives[i].derivative).balance() *
                IDerivative(derivatives[i].derivative).ethPerDerivative(
                    false
                )) / tvlEth;
            if (trueWeight < derivatives[i].weight) return i;
        }
        return 0;
    }

    /**
     * @notice - Only allow ETH being sent from derivative contracts.
     */
    receive() external payable {
        // Initialize a flag to track if the Ether sender is a registered derivative
        bool acceptSender;

        // Loop through the registered derivatives
        uint256 count = derivativeCount;
        for (uint256 i; i < count; ++i) {
            acceptSender = (address(derivatives[i].derivative) == msg.sender);
            if (acceptSender) {
                break;
            }
        }
        // Require that the sender is a registered derivative to accept the Ether transfer
        if (!acceptSender) revert InvalidDerivative();
    }
}
