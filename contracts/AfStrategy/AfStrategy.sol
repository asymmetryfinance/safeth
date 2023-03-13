// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IAfETH.sol";
import "../interfaces/uniswap/ISwapRouter.sol";
import "../interfaces/curve/ICrvEthPool.sol";
import "../interfaces/lido/IWStETH.sol";
import "../interfaces/lido/IstETH.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./AfStrategyStorage.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/// @title Contract that mints/burns safETH
/// @author Asymmetry Finance
contract AfStrategy is
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    AfStrategyStorage
{
    event ChangeMinAmount(uint256 indexed minAmount);
    event ChangeMaxAmount(uint256 indexed maxAmount);
    event StakingPaused(bool indexed paused);
    event UnstakingPaused(bool indexed paused);
    event Staked(address indexed recipient, uint ethIn, uint safEthOut);
    event Unstaked(address indexed recipient, uint ethOut, uint safEthIn);
    event WeightChange(uint indexed index, uint weight);
    event DerivativeAdded(
        address indexed contractAddress,
        uint weight,
        uint index
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
        ERC20Upgradeable.__ERC20_init(_tokenName, _tokenSymbol);
        _transferOwnership(msg.sender);
        minAmount = 5 ** 17;
        maxAmount = 200 ** 18;
    }

    /**
        @notice - Gets derivative value in regards to ETH for a specific index
        @param _index - index of the derivative to get ETH value
    */
    function derivativeValue(uint256 _index) external view returns (uint256) {
        return derivatives[_index].totalEthValue();
    }

    /**
        @notice - Stake your ETH into safETH
    */
    function stake() external payable {
        require(pauseStaking == false, "staking is paused");
        require(msg.value >= minAmount, "amount too low");
        require(msg.value <= maxAmount, "amount too high");

        uint256 underlyingValue = 0;

        for (uint i = 0; i < derivativeCount; i++)
            underlyingValue += derivatives[i].totalEthValue();

        uint256 totalSupply = IAfETH(safETH).totalSupply();
        uint256 preDepositPrice;
        if (totalSupply == 0) preDepositPrice = 10 ** 18;
        else preDepositPrice = (10 ** 18 * underlyingValue) / totalSupply;

        uint256 totalStakeValueEth = 0;
        for (uint i = 0; i < derivativeCount; i++) {
            uint256 weight = weights[i];
            IDerivative derivative = derivatives[i];
            if (weight == 0) continue;
            uint256 ethAmount = (msg.value * weight) / totalWeight;

            // This is slightly less than ethAmount because slippage
            uint256 depositAmount = derivative.deposit{value: ethAmount}();
            uint derivativeReceivedEthValue = (derivative.ethPerDerivative(
                depositAmount
            ) * depositAmount) / 10 ** 18;
            totalStakeValueEth += derivativeReceivedEthValue;
        }

        uint256 mintAmount = (totalStakeValueEth * 10 ** 18) / preDepositPrice;
        _mint(msg.sender, mintAmount);
        emit Staked(msg.sender, msg.value, mintAmount);
    }

    /**
        @notice - Unstake your safETH into ETH
        @param safEthAmount - amount of safETH to unstake into ETH
    */
    function unstake(uint256 safEthAmount) external {
        require(pauseUnstaking == false, "unstaking is paused");
        uint256 safEthTotalSupply = IAfETH(safETH).totalSupply();
        uint256 ethAmountBefore = address(this).balance;
        for (uint256 i = 0; i < derivativeCount; i++) {
            uint256 derivativeAmount = (derivatives[i].balance() *
                safEthAmount) / safEthTotalSupply;
            if (derivativeAmount == 0) continue;
            derivatives[i].withdraw(derivativeAmount);
        }
        _burn(msg.sender, safEthAmount);
        uint256 ethAmountAfter = address(this).balance;
        uint256 ethAmountToWithdraw = ethAmountAfter - ethAmountBefore;
        // solhint-disable-next-line
        (bool sent, ) = address(msg.sender).call{value: ethAmountToWithdraw}(
            ""
        );
        require(sent, "Failed to send Ether");
        emit Unstaked(msg.sender, ethAmountToWithdraw, safEthAmount);
    }

    /**
        @notice - Rebalance each derivative to resemble the weight set for it
        @dev - Depending on the balance of the derivative this could cause max slippage
    */
    function rebalanceToWeights() external onlyOwner {
        uint256 ethAmountBefore = address(this).balance;

        for (uint i = 0; i < derivativeCount; i++) {
            if (derivatives[i].balance() > 0)
                derivatives[i].withdraw(derivatives[i].balance());
        }
        uint256 ethAmountAfter = address(this).balance;
        uint256 ethAmountToRebalance = ethAmountAfter - ethAmountBefore;

        for (uint i = 0; i < derivativeCount; i++) {
            if (weights[i] == 0) continue;
            uint256 ethAmount = (ethAmountToRebalance * weights[i]) /
                totalWeight;
            // Price will change due to slippage
            derivatives[i].deposit{value: ethAmount}();
        }
        emit Rebalanced();
    }

    /**
        @notice - Adds new derivative to the index fund
        @dev - Weights are only in regards to each other, if you want exact weights either do the math off chain or set all derivates to the weights you want
        @param _derivativeIndex - index of the derivative you want to update the weight
        @param _weight - new weight for this derivative.
    */
    function adjustWeight(
        uint256 _derivativeIndex,
        uint256 _weight
    ) external onlyOwner {
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
        derivatives[derivativeCount] = IDerivative(_contractAddress);
        weights[derivativeCount] = _weight;
        derivativeCount++;

        uint256 localTotalWeight = 0;
        for (uint256 i = 0; i < derivativeCount; i++)
            localTotalWeight += weights[i];
        totalWeight = localTotalWeight;
        emit DerivativeAdded(_contractAddress, _weight, derivativeCount);
    }

    /**
        @notice - Sets the max slippage for a certain derivative index
        @param _derivativeIndex - index of the derivative you want to update the slippage
        @param _slippage - new slippage amount in wei
    */
    function setMaxSlippage(
        uint _derivativeIndex,
        uint _slippage
    ) external onlyOwner {
        derivatives[_derivativeIndex].setMaxSlippage(_slippage);
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

    receive() external payable {}
}
