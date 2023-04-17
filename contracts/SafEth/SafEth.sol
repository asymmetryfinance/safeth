// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "./SafEthStorage.sol";
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
    event ChangeMinAmount(uint256 indexed minAmount);
    event ChangeMaxAmount(uint256 indexed maxAmount);
    event StakingPaused(bool indexed paused);
    event UnstakingPaused(bool indexed paused);
    event SetMaxSlippage(uint256 indexed index, uint256 slippage);
    event Staked(
        address indexed recipient,
        uint256 ethIn,
        uint256 totalStakeValue,
        uint256 price
    );
    event Unstaked(address indexed recipient, uint256 ethOut, uint256 safEthIn);
    event WeightChange(uint256 indexed index, uint256 weight);
    event DerivativeAdded(
        address indexed contractAddress,
        uint256 weight,
        uint256 index
    );
    event Rebalanced();

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
        __ERC20_init(_tokenName, _tokenSymbol);
        __Ownable2Step_init();
        minAmount = 5 * 10 ** 17; // initializing with .5 ETH as minimum
        maxAmount = 200 * 10 ** 18; // initializing with 200 ETH as maximum
        __ReentrancyGuard_init();
    }

    /**
        @notice - Stake your ETH into safETH
        @dev - Deposits into each derivative based on its weight
        @dev - Mints safEth in a redeemable value which equals to the correct percentage of the total staked value
    */
    function stake(
        uint256 _minOut
    ) external payable nonReentrant returns (uint256 mintedAmount) {
        require(pauseStaking == false, "staking is paused");
        require(msg.value >= minAmount, "amount too low");
        require(msg.value <= maxAmount, "amount too high");

        uint256 underlyingValue = 0;

        // Getting underlying value in terms of ETH for each derivative
        for (uint256 i = 0; i < derivativeCount; i++)
            underlyingValue +=
                (derivatives[i].ethPerDerivative() * derivatives[i].balance()) /
                10 ** 18;

        uint256 safEthTotalSupply = totalSupply();
        uint256 preDepositPrice; // Price of safETH in regards to ETH
        if (safEthTotalSupply == 0 || underlyingValue == 0)
            preDepositPrice = 10 ** 18; // initializes with a price of 1
        else preDepositPrice = (10 ** 18 * underlyingValue) / safEthTotalSupply;

        uint256 totalStakeValueEth = 0; // total amount of derivatives staked by user in eth
        for (uint256 i = 0; i < derivativeCount; i++) {
            uint256 weight = weights[i];
            IDerivative derivative = derivatives[i];
            if (weight == 0) continue;
            uint256 ethAmount = (msg.value * weight) / totalWeight;
            if (ethAmount > 0) {
                // This is slightly less than ethAmount because slippage
                uint256 depositAmount = derivative.deposit{value: ethAmount}();
                uint256 derivativeReceivedEthValue = (derivative
                    .ethPerDerivative() * depositAmount) / 10 ** 18;
                totalStakeValueEth += derivativeReceivedEthValue;
            }
        }
        // mintAmount represents a percentage of the total assets in the system
        uint256 mintAmount = (totalStakeValueEth * 10 ** 18) / preDepositPrice;
        require(mintAmount > _minOut, "mint amount less than minOut");

        _mint(msg.sender, mintAmount);
        emit Staked(msg.sender, msg.value, totalStakeValueEth, approxPrice());
        return (mintAmount);
    }

    /**
        @notice - Unstake your safETH into ETH
        @dev - unstakes a percentage of safEth based on its total value
        @param _safEthAmount - amount of safETH to unstake into ETH
    */
    function unstake(
        uint256 _safEthAmount,
        uint256 _minOut
    ) external nonReentrant {
        require(pauseUnstaking == false, "unstaking is paused");
        require(_safEthAmount > 0, "amount too low");
        require(_safEthAmount <= balanceOf(msg.sender), "insufficient balance");

        uint256 safEthTotalSupply = totalSupply();
        uint256 ethAmountBefore = address(this).balance;

        for (uint256 i = 0; i < derivativeCount; i++) {
            // withdraw a percentage of each asset based on the amount of safETH
            uint256 derivativeAmount = (derivatives[i].balance() *
                _safEthAmount) / safEthTotalSupply;
            if (derivativeAmount == 0) continue; // if derivative empty ignore
            // Add check for a zero Ether received
            uint256 ethBefore = address(this).balance;
            derivatives[i].withdraw(derivativeAmount);
            require(
                address(this).balance - ethBefore != 0,
                "Receive zero Ether"
            );
        }
        _burn(msg.sender, _safEthAmount);
        uint256 ethAmountAfter = address(this).balance;
        uint256 ethAmountToWithdraw = ethAmountAfter - ethAmountBefore;
        require(ethAmountToWithdraw > _minOut);

        // solhint-disable-next-line
        (bool sent, ) = address(msg.sender).call{value: ethAmountToWithdraw}(
            ""
        );
        require(sent, "Failed to send Ether");
        emit Unstaked(msg.sender, ethAmountToWithdraw, _safEthAmount);
    }

    /**
        @notice - Rebalance each derivative to resemble the weight set for it
        @dev - Withdraws all derivative and re-deposit them to have the correct weights
        @dev - Depending on the balance of the derivative this could cause bad slippage
        @dev - If weights are updated then it will slowly change over time to the correct weight distribution
        @dev - Probably not going to be used often, if at all
    */
    function rebalanceToWeights() external onlyOwner {
        for (uint256 i = 0; i < derivativeCount; i++) {
            if (derivatives[i].balance() > 0)
                derivatives[i].withdraw(derivatives[i].balance());
        }
        uint256 ethAmountToRebalance = address(this).balance;

        for (uint256 i = 0; i < derivativeCount; i++) {
            if (weights[i] == 0 || ethAmountToRebalance == 0) continue;
            uint256 ethAmount = (ethAmountToRebalance * weights[i]) /
                totalWeight;
            // Price will change due to slippage
            derivatives[i].deposit{value: ethAmount}();
        }
        emit Rebalanced();
    }

    /**
        @notice - Adjusts weight for derivative at specific index
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
        require(_derivativeIndex < derivativeCount, "Index is out of range");

        weights[_derivativeIndex] = _weight;
        uint256 localTotalWeight = 0;
        for (uint256 i = 0; i < derivativeCount; i++)
            localTotalWeight += weights[i];
        totalWeight = localTotalWeight;
        emit WeightChange(_derivativeIndex, _weight);
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
            require(supported, "invalid derivative");
        } catch {
            // Contract doesn't support ERC-165
            revert("invalid contract");
        }

        derivatives[derivativeCount] = IDerivative(_contractAddress);
        weights[derivativeCount] = _weight;
        emit DerivativeAdded(_contractAddress, _weight, derivativeCount);
        derivativeCount++;

        uint256 localTotalWeight = 0;
        for (uint256 i = 0; i < derivativeCount; i++)
            localTotalWeight += weights[i];
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
        derivatives[_derivativeIndex].setMaxSlippage(_slippage);
        emit SetMaxSlippage(_derivativeIndex, _slippage);
    }

    /**
        @notice - Sets the minimum amount a user is allowed to stake
        @param _minAmount - amount to set as minimum stake value
    */
    function setMinAmount(uint256 _minAmount) external onlyOwner {
        minAmount = _minAmount;
        emit ChangeMinAmount(minAmount);
    }

    /**
        @notice - Owner only function that sets the maximum amount a user is allowed to stake
        @param _maxAmount - amount to set as maximum stake value
    */
    function setMaxAmount(uint256 _maxAmount) external onlyOwner {
        maxAmount = _maxAmount;
        emit ChangeMaxAmount(maxAmount);
    }

    /**
        @notice - Owner only function that Enables/Disables the stake function
        @param _pause - true disables staking / false enables staking
    */
    function setPauseStaking(bool _pause) external onlyOwner {
        pauseStaking = _pause;
        emit StakingPaused(pauseStaking);
    }

    /**
        @notice - Owner only function that enables/disables the unstake function
        @param _pause - true disables unstaking / false enables unstaking
    */
    function setPauseUnstaking(bool _pause) external onlyOwner {
        pauseUnstaking = _pause;
        emit UnstakingPaused(pauseUnstaking);
    }

    /**
     * @notice - Get the approx price of safEth.
     * @dev - This is approximate because of slippage when acquiring / selling the underlying
     */
    function approxPrice() public view returns (uint256) {
        uint256 underlyingValue = 0;
        for (uint256 i = 0; i < derivativeCount; i++)
            underlyingValue +=
                (derivatives[i].ethPerDerivative() * derivatives[i].balance()) /
                10 ** 18;
        return (10 ** 18 * underlyingValue) / totalSupply();
    }

    receive() external payable {
        // Initialize a flag to track if the Ether sender is a registered derivative
        bool acceptSender;

        // Loop through the registered derivatives
        uint256 count = derivativeCount;
        for (uint256 i; i < count; ++i) {
            acceptSender = (address(derivatives[i]) == msg.sender);
            if (acceptSender) {
                break;
            }
        }
        // Require that the sender is a registered derivative to accept the Ether transfer
        require(acceptSender, "Not a derivative contract");
    }
}
