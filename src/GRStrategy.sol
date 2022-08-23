// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/curve/ICurve.sol";
import {ISwapRouter} from "uniswap/interfaces/ISwapRouter.sol";

/**
 * @title Golden Ratio Base ETH Strategy
 * @notice This strategy autocompounds Convex rewards from the PUSD/USDC/USDT/DAI Curve pool
 * @dev The strategy deposits 33.3% ETH in the ETH/grETH Curve pool, swaps 33.3% ETH for CVX and locks up CVX,
 * and deposits remaining 33.3% ETH into liquid staked ETH Balancer pool
 */
contract GRStrategy {
    // Uniswap Router
    ISwapRouter public immutable swapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    // WETH token address
    // https://docs.uniswap.org/protocol/reference/deployments
    address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Multi-step Deposit function to deposit funds into CRV pool, lock up CVX, deposit into BAL pool
    function deposit() public {}

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");
    }

    // Swap for an exact amount of CVX based on input
    function swapExactInputSingleSwap() internal {}

    // Compound earnings and charge performance fee
    function _harvest() internal {}

    // charge performance fee
    function chargeFees() internal {}

    // Calculate the total underlaying 'want' held by the strategy.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    // Calculate how much 'want' (WETH) this contract holds.
    function balanceOfWant() public view returns (uint256) {}

    // Calculate how much 'want' the strategy has working in the strategy.
    function balanceOfPool() public view returns (uint256) {}
}
