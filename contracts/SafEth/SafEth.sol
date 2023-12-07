// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "./SafEthStorage.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title Contract that mints/burns and provides owner functions for safETH
/// @author Asymmetry Finance
contract SafEth is
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
        @param _tokenName - Name of erc20
        @param _tokenSymbol - Symbol of erc20
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
    }

    /**
        @notice - Function to initialize values for enabledDerivatives
    */
    function initializeV2() external {
        if (hasInitializedV2) revert AlreadySet();
        enabledDerivatives = [0, 1, 2];
        enabledDerivativeCount = 3;
        maxPreMintAmount = 2 ether;
        singleDerivativeThreshold = 10 ether;
        hasInitializedV2 = true;
    }

    /**
     * @notice Sets a recipient address as blacklisted to receive tokens
     * @param _recipient - Recipient address to set blacklisted on/off
     * @param _isBlacklisted - True or False
     */
    function setBlacklistedRecipient(
        address _recipient,
        bool _isBlacklisted
    ) external onlyOwner {
        blacklistedRecipients[_recipient] = _isBlacklisted;
    }

    /**
     * @notice Sets a sender address as whitelisted to send to blacklisted addressses
     * @param _sender - Sender address to set whitelisted on/off
     * @param _isWhitelisted - True or False
     */
    function setWhitelistedSender(
        address _sender,
        bool _isWhitelisted
    ) external onlyOwner {
        whitelistedSenders[_sender] = _isWhitelisted;
    }

    /**
     * @notice Sets the eth amount at which it will use standard weighting vs buying a single derivative
     * @param _amount - Amount of eth where it will switch to standard weighting
     */
    function setSingleDerivativeThreshold(uint256 _amount) external onlyOwner {
        singleDerivativeThreshold = _amount;
        emit SingleDerivativeThresholdUpdated(_amount);
    }

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
        if (shouldPremintStake()) return doPreMintedStake(_minOut);
        depositPrice = approxPrice(true);
        return (doMultiStake(_minOut, depositPrice), depositPrice);
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

        uint256 unstakePrice = (_safEthAmount * 1e18) / ethAmountToWithdraw;
        emit Unstaked(
            msg.sender,
            ethAmountToWithdraw,
            _safEthAmount,
            unstakePrice,
            false
        );
    }

    /**
        @notice - Premints safEth for future users
        @param _minAmount - Minimum amount to stake
        @param _balanceAmount - Amount of the current ethToClaim balance to use for premint
        @param _overWriteFloorPrice - Should overwrite floorPrice even if it's higher than depositPrice
     */
    function fundPreMintStake(
        uint256 _minAmount,
        uint256 _balanceAmount,
        bool _overWriteFloorPrice
    ) external payable onlyOwner returns (uint256) {
        uint256 amount = msg.value;
        if (_balanceAmount > 0) {
            amount += _balanceAmount;
            ethToClaim -= _balanceAmount;
        }
        if (amount <= maxPreMintAmount) revert PremintTooLow();

        (uint256 mintedAmount, uint256 depositPrice) = this.stake{
            value: amount
        }(_minAmount);
        floorPrice = (floorPrice < depositPrice || _overWriteFloorPrice)
            ? depositPrice
            : floorPrice;
        unchecked {
            safEthToClaim += mintedAmount;
        }
        emit PreMintStake(amount, mintedAmount, depositPrice);
        return mintedAmount;
    }

    /**
        @notice - Adds ETH to allow for users to unstake
        @param _updateFloorPrice - Should update floorPrice to the current price
     */
    function fundPreMintUnstake(
        bool _updateFloorPrice
    ) external payable onlyOwner {
        unchecked {
            ethToClaim += msg.value;
        }
        if (_updateFloorPrice) {
            floorPrice = approxPrice(true);
        }
        emit PreMintUnstake(msg.value);
    }

    /**
        @notice - Claims ETH that was used to acquire preminted safEth
     */
    function withdrawPremintedEth() external onlyOwner {
        uint256 _ethToClaim = ethToClaim;
        ethToClaim = 0;
        // solhint-disable-next-line
        (bool sent, ) = address(msg.sender).call{value: _ethToClaim}("");
        if (!sent) revert FailedToSend();
    }

    /**
        @notice - Claims SafEth that was used to acquire preminted ETH
     */
    function withdrawPremintedSafEth() external onlyOwner {
        uint256 _safEthToClaim = safEthToClaim;
        safEthToClaim = 0;
        transfer(msg.sender, _safEthToClaim);
    }

    /**
     * @notice - Allows owner to rebalance between 2 derivatives, selling 1 for the other
     * @param _sellDerivativeIndex - Index of the derivative to sell
     * @param _buyDerivativeIndex - Index of the derivative to buy
     * @param _sellAmount - Amount of the derivative to sell
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
        @param _derivativeIndex - Index of the derivative you want to update the weight
        @param _weight - New weight for this derivative.
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
        @param _derivativeIndex - Index of the derivative you want to disable
    */
    function disableDerivative(uint256 _derivativeIndex) external onlyOwner {
        if (_derivativeIndex >= derivativeCount) revert IndexOutOfBounds();
        if (!derivatives[_derivativeIndex].enabled) revert NotEnabled();

        derivatives[_derivativeIndex].enabled = false;
        setTotalWeight();

        uint256[] memory tempArray = new uint256[](
            enabledDerivatives.length - 1
        );
        uint256 tempIndex = 0;
        for (uint256 i = 0; i < enabledDerivatives.length; i++) {
            if (enabledDerivatives[i] != _derivativeIndex) {
                tempArray[tempIndex] = enabledDerivatives[i];
                tempIndex++;
            }
        }
        enabledDerivatives = tempArray;
        unchecked {
            --enabledDerivativeCount;
        }

        emit DerivativeDisabled(_derivativeIndex);
    }

    /**
        @notice - Enables Derivative based on derivative index
        @param _derivativeIndex - Index of the derivative you want to enable
    */
    function enableDerivative(uint256 _derivativeIndex) external onlyOwner {
        if (_derivativeIndex >= derivativeCount) revert IndexOutOfBounds();
        if (derivatives[_derivativeIndex].enabled) revert AlreadyEnabled();

        derivatives[_derivativeIndex].enabled = true;
        enabledDerivatives.push(_derivativeIndex);

        setTotalWeight();

        unchecked {
            ++enabledDerivativeCount;
        }
        emit DerivativeEnabled(_derivativeIndex);
    }

    /**
        @notice - Adds new derivative to the index fund
        @param _contractAddress - Address of the derivative contract launched by AF
        @param _weight - New weight for this derivative. 
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
        enabledDerivatives.push(derivativeCount);
        emit DerivativeAdded(_contractAddress, _weight, derivativeCount);
        unchecked {
            ++derivativeCount;
            ++enabledDerivativeCount;
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
        @notice - Sets the minimum amount a user is allowed to stake
        @param _minAmount - Amount to set as minimum stake value
    */
    function setMinAmount(uint256 _minAmount) external onlyOwner {
        emit ChangeMinAmount(minAmount, _minAmount);
        minAmount = _minAmount;
    }

    /**
        @notice - Owner only function that sets the maximum amount a user is allowed to stake
        @param _maxAmount - Amount to set as maximum stake value
    */
    function setMaxAmount(uint256 _maxAmount) external onlyOwner {
        emit ChangeMaxAmount(maxAmount, _maxAmount);
        maxAmount = _maxAmount;
    }

    /**
        @notice - Owner only function that Enables/Disables the stake function
        @param _pause - True disables staking / False enables staking
    */
    function setPauseStaking(bool _pause) external onlyOwner {
        if (pauseStaking == _pause) revert AlreadySet();
        pauseStaking = _pause;
        emit StakingPaused(_pause);
    }

    /**
        @notice - Sets the maximum amount a user can premint in one transaction
        @param _amount - Amount to set as maximum premint value
        @dev - This is to prevent a whale from coming in and taking all the preminted funds
        @dev - A user can stake multiple times and still receive the preminted funds
    */
    function setMaxPreMintAmount(uint256 _amount) external onlyOwner {
        maxPreMintAmount = _amount;
        emit MaxPreMintAmount(_amount);
    }

    /**
        @notice - Owner only function that enables/disables the unstake function
        @param _pause - True disables unstaking / False enables unstaking
    */
    function setPauseUnstaking(bool _pause) external onlyOwner {
        if (pauseUnstaking == _pause) revert AlreadySet();
        pauseUnstaking = _pause;
        emit UnstakingPaused(_pause);
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

    /**
     * @notice - Decides if the contract can send preminted safEth (to save gas) instead of minting new
     * @return - True or False if it can use preminted or not
     */
    function shouldPremintStake() private view returns (bool) {
        if (floorPrice == 0) return false;
        uint256 amount = (msg.value * 1e18) / floorPrice;
        return amount <= safEthToClaim && msg.value <= maxPreMintAmount;
    }

    /**
     * @notice - Decides if the contract can handle passing in ETH instead of fully unstaking
     * @param _amount - Amount of SafEth to unstake
     * @return - True or False if it can use unstaked with premint or not
     */
    function shouldPremintUnstake(
        uint256 _amount
    ) private view returns (bool, uint256, uint256) {
        uint256 priceToClaim = approxPrice(true);
        uint256 amountOut = (_amount * priceToClaim) / 1e18;
        return (
            amountOut <= ethToClaim && amountOut <= maxPreMintAmount,
            priceToClaim,
            amountOut
        );
    }

    /**
     * @notice - Stakes by using preminted supply instead of minting new
     * @param _minOut - Minimum amount of safEth to receive or revert
     * @return mintedAmount - Amount of safEth token sent from the preminted supply
     * @return preMintPrice - Price at which preminted safEth was sold to user upon staking
     */
    function doPreMintedStake(
        uint256 _minOut
    ) private returns (uint256 mintedAmount, uint256 preMintPrice) {
        preMintPrice = floorPrice;
        mintedAmount = (msg.value * 1e18) / preMintPrice;
        if (mintedAmount < _minOut) revert PremintTooLow();
        ethToClaim += msg.value;
        safEthToClaim -= mintedAmount;
        IERC20(address(this)).transfer(msg.sender, mintedAmount);
        emit Staked(
            msg.sender,
            msg.value,
            (mintedAmount * preMintPrice) / 1e18,
            preMintPrice,
            true
        );
    }

    /**
     * @notice - Unstakes by using internal ETH instead of unstaking the derivatives
     * @param _amount - Amount of safEth to unstake
     * @param _minOut - Minimum amount of ETH to receive or revert
     * @return ethToRedeem - Amount of ETH sent from the preminted supply
     */
    function preMintUnstake(
        uint256 _amount,
        uint256 _minOut
    ) public returns (uint256 ethToRedeem) {
        (
            bool shouldPremint,
            uint256 price,
            uint256 ethToRedeem
        ) = shouldPremintUnstake(_amount);
        if (!shouldPremint) revert AmountTooLow();
        _transfer(msg.sender, address(this), _amount);
        safEthToClaim += _amount;
        if (ethToRedeem < _minOut) revert PremintTooLow();
        ethToClaim -= ethToRedeem;

        // solhint-disable-next-line
        (bool sent, ) = address(msg.sender).call{value: ethToRedeem}("");
        if (!sent) revert FailedToSend();

        emit Unstaked(msg.sender, ethToRedeem, _amount, price, true);
    }

    /**
     * @notice - Stakes into all derivatives
     * @param _minOut - Minimum amount of safEth to receive or revert
     * @param price - Price safEth price passed from approxPrice()
     * @return mintedAmount - Amount of safEth token minted
     */
    function doMultiStake(
        uint256 _minOut,
        uint256 price
    ) private returns (uint256 mintedAmount) {
        if (enabledDerivativeCount == 0) revert NoEnabledDerivatives();
        uint256 totalStakeValueEth = 0;
        uint256 amountStaked = 0;

        for (uint256 i = 0; i < enabledDerivativeCount; i++) {
            uint256 index = enabledDerivatives[i];
            uint256 weight = derivatives[index].weight;

            if (weight == 0) continue;
            IDerivative derivative = derivatives[index].derivative;
            uint256 ethAmount = i == enabledDerivativeCount - 1
                ? msg.value - amountStaked
                : (msg.value * weight) / totalWeight;

            amountStaked += ethAmount;
            uint256 depositAmount = derivative.deposit{value: ethAmount}();
            uint256 derivativeReceivedEthValue = (derivative.ethPerDerivative(
                true
            ) * depositAmount);
            totalStakeValueEth += derivativeReceivedEthValue;
        }
        mintedAmount = (totalStakeValueEth) / price;
        if (mintedAmount < _minOut) revert MintedAmountTooLow();

        _mint(msg.sender, mintedAmount);
        emit Staked(
            msg.sender,
            msg.value,
            totalStakeValueEth / 1e18,
            price,
            false
        );
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
