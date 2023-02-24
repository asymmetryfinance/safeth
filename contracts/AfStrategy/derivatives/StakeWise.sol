// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../interfaces/Iderivative.sol";
import "../../interfaces/frax/IsFrxEth.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../../interfaces/uniswap/ISwapRouter.sol";
import "hardhat/console.sol";
import "../../interfaces/uniswap/IUniswapV3Pool.sol";
import "../../interfaces/IWETH.sol";
import "../../interfaces/stakewise/IStakewiseStaker.sol";
// Stakewise unique features:
// stake to receive sETH2 (stablecoin)
// Rewards are accumulated daily in rEth2 (stablecoin)
// So theres really 2 underlying tokens here.

// There is an "activation period" that applies to larger deposits but the deposit size required is currently HUGE
// For simplicity we throw if our deposit requires an activation period.
// This brings up another issue -- the strategy contract needs to deal with derivatives throwing (maybe just return their funds for that derivative???)
contract StakeWise is IDERIVATIVE, Ownable {
    using SafeMath for uint256;

    address public constant uniswapRouter =
        0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address public constant sEth2 =
        0xFe2e637202056d30016725477c5da089Ab0A043A;
    address public constant rEth2 =
        0x20BC832ca081b91433ff6c17f85701B6e92486c5;
    address public constant rEth2Seth2Pool = 0xa9ffb27d36901F87f1D0F20773f7072e38C5bfbA;
    address public constant seth2WethPool = 0x7379e81228514a1D2a6Cf7559203998E20598346;
    address public constant wEth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant staker = 0xC874b064f465bdD6411D45734b56fac750Cda29A;
    
    constructor() {
        _transferOwnership(msg.sender);
    }

    function withdraw(uint256 amount) public onlyOwner {

        sellAllReth2();

        // Theres a chance balance() returns more than they actually have to withdraew because of rEth2/sEth2 price variations
        // if they tried to withdraw more than they have just set it to their balance
        uint256 withdrawAmount;
        if(amount > IERC20(sEth2).balanceOf(address(this))) withdrawAmount = IERC20(sEth2).balanceOf(address(this));
        else withdrawAmount = amount;
        uint256 wEthReceived = sellSeth2ForWeth(amount);
        IWETH(wEth).withdraw(wEthReceived);
        address(msg.sender).call{value: address(this).balance}("");
    }

    function deposit() public payable onlyOwner returns (uint256) {
        uint256 balanceBefore = IERC20(sEth2).balanceOf(address(this));
        IStakewiseStaker(staker).stake{value: msg.value}();
        uint256 balanceAfter = IERC20(sEth2).balanceOf(address(this));
        return balanceAfter - balanceBefore;
    }

    function ethPerDerivative(uint256 amount) public view returns (uint256) {
        if(amount == 0) return 0;
        uint256 wethOutput = estimatedSellSeth2Output(amount); // we can assume weth is always 1-1 with eth
        return wethOutput;
    }

    function totalEthValue() public view returns (uint256) {
        return ethPerDerivative(balance());
    }

    // This is more like virtualBalance because its estimating total sEth2 holding based on rEth price2
    function balance() public view returns (uint256) {
        // seth2Balance + estimated seth2 value of reth holdings
        return IERC20(sEth2).balanceOf(address(this)) + estimatedSellReth2Output(IERC20(rEth2).balanceOf(address(this)));
    }

    function sellAllReth2() public returns (uint) {
        uint256 rEth2Balance = IERC20(rEth2).balanceOf(address(this));

        if(rEth2Balance == 0) return 0;

        IERC20(rEth2).approve(uniswapRouter, rEth2Balance);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: rEth2,
                tokenOut: sEth2,
                fee: 500,
                recipient: address(this),
                amountIn: rEth2Balance,
                amountOutMinimum: 1, // this isnt great
                sqrtPriceLimitX96: 0
            });
        return ISwapRouter(uniswapRouter).exactInputSingle(params);
    }

    function sellSeth2ForWeth(uint256 amount) public returns (uint) {
        IERC20(sEth2).approve(uniswapRouter, IERC20(sEth2).balanceOf(address(this)));
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: sEth2,
                tokenOut: wEth,
                fee: 500,
                recipient: address(this),
                amountIn: amount,
                amountOutMinimum: 1, // this isnt great
                sqrtPriceLimitX96: 0
            });
        return ISwapRouter(uniswapRouter).exactInputSingle(params);
    }

    

    function estimatedSellSeth2Output(uint256 amount) public view returns (uint) {
        //IERC20(sEth2).balanceOf(address(this))
        return uint256(uint256(poolPrice(seth2WethPool)).mul(amount)).div(10 ** 18);
    }

    function estimatedSellReth2Output(uint256 amount) public view returns (uint) {
        return uint256(uint256(poolPrice(rEth2Seth2Pool)).mul(amount)).div(10 ** 18);
    }

    // TODO figure out if this price is rEth2/sEth2 or sEth2/rEth2
    // Prices are nearly the same so its hard to tell
    function poolPrice(address poolAddress)
        public
        view
        returns (uint256)
    {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtPriceX96,,,,,,) =  pool.slot0();
        return uint(sqrtPriceX96).mul(uint(sqrtPriceX96)).mul(1e18) >> (96 * 2);
    }

    receive() external payable {}
}
