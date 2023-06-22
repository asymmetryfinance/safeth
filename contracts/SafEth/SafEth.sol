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
     * @notice - modifier for transfer() and transferFrom() for owner enforcing blacklists
     * @param sender - sender address
     * @param recipient - recipient address
     */
    modifier checkBlacklist(address sender, address recipient) {
        if (blacklistedRecipients[recipient] && !whitelistedSenders[sender]) {
            revert BlacklistedAddress();
        }
        _;
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
    ) public override checkBlacklist(sender, recipient) returns (bool) {
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
    ) public override checkBlacklist(msg.sender, _recipient) returns (bool) {
        return super.transfer(_recipient, _amount);
    }

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
        if (shouldPremint(depositPrice))
            return doPreMintedStake(_minOut, depositPrice);
        if (msg.value < singleDerivativeThreshold)
            return (doSingleStake(_minOut, depositPrice), depositPrice);
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
     * @notice - find derivative that is underweight relative to target weights
     * @return - a derivative index that is underweight relative to target weights
     */
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
     * @notice - decides if the contract can send preminted safEth (to save gas) instead of minting new
     * @param price - price safEth price passed from approxPrice()
     * @return - true or false if it can use preminted or not
     */
    function shouldPremint(uint256 price) private view returns (bool) {
        uint256 preMintPrice = price < floorPrice ? floorPrice : price;
        uint256 amount = (msg.value * 1e18) / preMintPrice;
        return amount <= preMintedSupply && msg.value <= maxPreMintAmount;
    }

    /**
     * @notice - stakes by using preminted supply instead of minting new
     * @param _minOut - minimum amount of safEth to receive or revert
     * @param price - price safEth price passed from approxPrice()
     * @return mintedAmount - amount of safEth token sent from the preminted supply
     * @return preMintPrice - price at which preminted safEth was sold to user upon staking
     */
    function doPreMintedStake(
        uint256 _minOut,
        uint256 price
    ) private returns (uint256 mintedAmount, uint256 preMintPrice) {
        preMintPrice = price < floorPrice ? floorPrice : price;
        mintedAmount = (msg.value * 1e18) / preMintPrice;
        if (mintedAmount < _minOut) revert PremintTooLow();
        ethToClaim += msg.value;
        preMintedSupply -= mintedAmount;
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
     * @notice - stakes by using a single derivative to save gas
     * @param _minOut - minimum amount of safEth to receive or revert
     * @param price - price safEth price passed from approxPrice()
     * @return mintedAmount - amount of safEth token minted
     */
    function doSingleStake(
        uint256 _minOut,
        uint256 price
    ) private returns (uint256 mintedAmount) {
        uint256 totalStakeValueEth = 0;
        IDerivative derivative = derivatives[firstUnderweightDerivativeIndex()]
            .derivative;
        uint256 depositAmount = derivative.deposit{value: msg.value}();
        uint256 derivativeReceivedEthValue = (derivative.ethPerDerivative(
            true
        ) * depositAmount);
        totalStakeValueEth += derivativeReceivedEthValue;
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
     * @notice - stakes into all derivatives
     * @param _minOut - minimum amount of safEth to receive or revert
     * @param price - price safEth price passed from approxPrice()
     * @return mintedAmount - amount of safEth token minted
     */
    function doMultiStake(
        uint256 _minOut,
        uint256 price
    ) private returns (uint256 mintedAmount) {
        uint256 totalStakeValueEth = 0;
        uint256 amountStaked = 0;
        for (uint256 i = 0; i < derivativeCount; i++) {
            if (!derivatives[i].enabled) continue;
            uint256 weight = derivatives[i].weight;
            if (weight == 0) continue;
            IDerivative derivative = derivatives[i].derivative;
            uint256 ethAmount = i == derivativeCount - 1
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
