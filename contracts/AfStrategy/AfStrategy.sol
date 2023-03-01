// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IAfETH.sol";
import "../interfaces/uniswap/ISwapRouter.sol";
import "../interfaces/curve/ICrvEthPool.sol";
import "../interfaces/lido/IWStETH.sol";
import "../interfaces/lido/IstETH.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./AfStrategyStorage.sol";

contract AfStrategy is Initializable, OwnableUpgradeable, AfStrategyStorage {
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

    // This replaces the constructor for upgradeable contracts
    function initialize(address _safETH) public initializer {
        _transferOwnership(msg.sender);
        safETH = _safETH;
    }

    function setMaxSlippage(uint derivativeIndex, uint slippage) public onlyOwner {
        derivatives[derivativeIndex].setMaxSlippage(slippage);
    }

    function addDerivative(
        address contractAddress,
        uint256 weight
    ) public onlyOwner {
        derivatives[derivativeCount] = IDERIVATIVE(contractAddress);
        weights[derivativeCount] = weight;
        derivativeCount++;

        uint256 localTotalWeight = 0;
        for (uint256 i = 0; i < derivativeCount; i++)
            localTotalWeight += weights[i];
        totalWeight = localTotalWeight;
        emit DerivativeAdded(contractAddress, weight, derivativeCount);
    }

    function adjustWeight(uint256 index, uint256 weight) public onlyOwner {
        weights[index] = weight;
        uint256 localTotalWeight = 0;
        for (uint256 i = 0; i < derivativeCount; i++)
            localTotalWeight += weights[i];
        totalWeight = localTotalWeight;
        emit WeightChange(index, weight);
    }

    function rebalanceToWeights() public onlyOwner {
        uint256 ethAmountBefore = address(this).balance;

        for (uint i = 0; i < derivativeCount; i++)
            derivatives[i].withdraw(derivatives[i].balance());
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

    function derivativeValue(uint256 index) public view returns (uint256) {
        return derivatives[index].totalEthValue();
    }

    function underlyingValue() public view returns (uint256) {
        uint256 total = 0;
        for (uint i = 0; i < derivativeCount; i++)
            total += derivatives[i].totalEthValue();
        return total;
    }

    function valueBySupply() public view returns (uint256) {
        uint256 totalSupply = IAfETH(safETH).totalSupply();
        if (totalSupply == 0) return 10 ** 18;
        return (10 ** 18 * underlyingValue()) / totalSupply;
    }

    function stake() public payable {
        require(pauseStaking == false, "staking is paused");
        uint256 preDepositPrice = valueBySupply();

        uint256 totalStakeValueEth = 0;
        for (uint i = 0; i < derivativeCount; i++) {
            if (weights[i] == 0) continue;
            uint256 ethAmount = (msg.value * weights[i]) / totalWeight;

            // This is slightly less than ethAmount because slippage
            uint256 depositAmount = derivatives[i].deposit{value: ethAmount}();
            uint derivativeReceivedEthValue = derivatives[i].ethPerDerivative(
                depositAmount
            );
            totalStakeValueEth += derivativeReceivedEthValue;
        }

        uint256 mintAmount = (totalStakeValueEth * 10 ** 18) / preDepositPrice;
        IAfETH(safETH).mint(msg.sender, mintAmount);
        emit Staked(msg.sender, msg.value, mintAmount);
    }

    function unstake(uint256 safEthAmount) public {
        require(pauseUnstaking == false, "unstaking is paused");
        uint256 safEthTotalSupply = IAfETH(safETH).totalSupply();
        uint256 ethAmountBefore = address(this).balance;
        for (uint256 i = 0; i < derivativeCount; i++) {
            uint256 derivativeAmount = (derivatives[i].balance() *
                safEthAmount) / safEthTotalSupply;
            if (derivativeAmount == 0) continue;
            derivatives[i].withdraw(derivativeAmount);
        }
        IAfETH(safETH).burn(msg.sender, safEthAmount);
        uint256 ethAmountAfter = address(this).balance;
        uint256 ethAmountToWithdraw = ethAmountAfter - ethAmountBefore;
        // solhint-disable-next-line
        (bool sent, ) = address(msg.sender).call{value: ethAmountToWithdraw}(
            ""
        );
        require(sent, "Failed to send Ether");
        emit Unstaked(msg.sender, ethAmountToWithdraw, safEthAmount);
    }

    function setPauseStaking(bool _pause) public onlyOwner {
        pauseStaking = _pause;
        emit StakingPaused(_pause);
    }

    function setPauseUnstaking(bool _pause) public onlyOwner {
        pauseUnstaking = _pause;
        emit UnstakingPaused(_pause);
    }

    receive() external payable {}
}
