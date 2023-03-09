// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IWETH.sol";
import "../../interfaces/IAfETH.sol";
import "../../interfaces/uniswap/ISwapRouter.sol";
import "../../interfaces/curve/ICrvEthPool.sol";
import "../../interfaces/rocketpool/RocketDepositPoolInterface.sol";
import "../../interfaces/rocketpool/RocketStorageInterface.sol";
import "../../interfaces/rocketpool/RocketTokenRETHInterface.sol";
import "../../interfaces/lido/IWStETH.sol";
import "../../interfaces/lido/IstETH.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./AfStrategyV2MockStorage.sol";
import "../derivatives/SfrxEth.sol";
import "../derivatives/Reth.sol";
import "../derivatives/WstEth.sol";

contract AfStrategyV2Mock is
    Initializable,
    OwnableUpgradeable,
    AfStrategyV2MockStorage
{
    event StakingPaused(bool paused);
    event UnstakingPaused(bool paused);
    event Staked(address recipient, uint ethIn, uint safEthOut);
    event Unstaked(address recipient, uint ethOut, uint safEthIn);

    uint256 public maxSlippage;

    function newFunction() public {
        newFunctionCalled = true;
    }

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

    function addDerivative(
        address contractAddress,
        uint256 weight
    ) public onlyOwner {
        derivatives[derivativeCount] = IDerivative(contractAddress);
        weights[derivativeCount] = weight;
        derivativeCount++;
    }

    function adjustWeight(uint index, uint weight) public onlyOwner {
        weights[index] = weight;
    }

    function stake() public payable {
        require(pauseStaking == false, "staking is paused");

        uint256 underlyingValue = 0;
        for (uint i = 0; i < derivativeCount; i++)
            underlyingValue += derivatives[i].totalEthValue();

        uint256 totalSupply = IAfETH(safETH).totalSupply();
        uint256 preDepositPrice;
        if (totalSupply == 0) preDepositPrice = 10 ** 18;
        else preDepositPrice = (10 ** 18 * underlyingValue) / totalSupply;

        uint256 totalStakeValueEth = 0;
        for (uint i = 0; i < derivativeCount; i++) {
            if (weights[i] == 0) continue;
            uint256 ethAmount = (msg.value * weights[i]) / totalWeight;

            // This is slightly less than ethAmount because slippage
            uint256 depositAmount = derivatives[i].deposit{value: ethAmount}();
            uint derivativeReceivedEthValue = (derivatives[i]
                .ethPerDerivative() * depositAmount) / 10 ** 18;
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
        for (uint i = 0; i < derivativeCount; i++)
            derivatives[i].withdraw(
                (derivatives[i].balance() * safEthAmount) / safEthTotalSupply
            );
        IAfETH(safETH).burn(msg.sender, safEthAmount);
        uint256 ethAmountAfter = address(this).balance;
        uint256 ethAmountToWithdraw = ethAmountAfter - ethAmountBefore;
        // solhint-disable-next-line
        (bool sent, ) = address(msg.sender).call{value: ethAmountToWithdraw}(
            ""
        );
        require(sent, "Failed to send Ether");
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
