// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IAfETH.sol";
import "../interfaces/uniswap/ISwapRouter.sol";
import "../interfaces/curve/ICrvEthPool.sol";
import "../interfaces/rocketpool/RocketDepositPoolInterface.sol";
import "../interfaces/rocketpool/RocketStorageInterface.sol";
import "../interfaces/rocketpool/RocketTokenRETHInterface.sol";
import "../interfaces/lido/IWStETH.sol";
import "../interfaces/lido/IstETH.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./AfStrategyStorage.sol";
import "./derivatives/SfrxEth.sol";
import "./derivatives/Reth.sol";
import "./derivatives/WstEth.sol";

contract AfStrategy is Initializable, OwnableUpgradeable, AfStrategyStorage {
    event StakingPaused(bool paused);
    event UnstakingPaused(bool paused);
    event Staked(address recipient, uint ethIn, uint safEthOut);
    event Unstaked(address recipient, uint ethOut, uint safEthIn);
    event WeightChange(uint index, uint weight);
    event DerivativeAdded(address contractAddress, uint weight, uint index);

    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // This replaces the constructor for upgradeable contracts
    function initialize(address _afETH) public initializer {
        _transferOwnership(msg.sender);
        afETH = _afETH;
    }

    function addDerivative(address contractAddress, uint256 weight) public onlyOwner {
        derivatives[derivativeCount] = IDERIVATIVE(contractAddress);
        weights[derivativeCount] = weight;
        emit DerivativeAdded(contractAddress, weight, derivativeCount);
        derivativeCount++;
    }

    function adjustWeight(uint index, uint weight) public onlyOwner {
        weights[index] = weight;
        emit WeightChange(index, weight);
    }

    function price() public view returns(uint256) {
        uint256 totalSupply = IAfETH(afETH).totalSupply();
        uint256 underlyingValue = 0;
        for(uint i=0;i<derivativeCount;i++) underlyingValue += derivatives[i].totalEthValue();
        if(totalSupply == 0) return 10 ** 18;
        return 10 ** 18 * underlyingValue / totalSupply;
    }

    function stake() public payable {
        require(pauseStaking == false, "staking is paused");
        uint256 preDepositPrice = price();

        uint totalWeight =0;
        for(uint i=0;i<derivativeCount;i++) totalWeight += weights[i];

        uint256 totalStakeValueEth = 0;
        for(uint i=0;i<derivativeCount;i++) {
            uint256 ethAmount = (msg.value * weights[i]) / totalWeight;
            totalStakeValueEth += derivatives[i].ethPerDerivative(derivatives[i].deposit{value: ethAmount}());
        }
        uint256 mintAmount = (totalStakeValueEth * 10 ** 18) / preDepositPrice;
        IAfETH(afETH).mint(msg.sender, mintAmount);
        emit Staked(msg.sender, msg.value, mintAmount);
    }

    function unstake(uint256 safEthAmount) public {
        require(pauseUnstaking == false, "unstaking is paused");
        uint256 safEthTotalSupply = IAfETH(afETH).totalSupply();
        uint256 ethAmountBefore = address(this).balance;
        for(uint i=0;i<derivativeCount;i++) derivatives[i].withdraw((derivatives[i].balance() * safEthAmount) / safEthTotalSupply);
        IAfETH(afETH).burn(msg.sender, safEthAmount);
        uint256 ethAmountAfter = address(this).balance;
        uint256 ethAmountToWithdraw = ethAmountAfter - ethAmountBefore;
        // solhint-disable-next-line
        address(msg.sender).call{value: ethAmountToWithdraw}("");
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
