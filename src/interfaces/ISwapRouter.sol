// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @dev Interface for
 * @dev See original implementation in official repository:
 * Link:
 */
interface ISwapRouter {
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external;

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params)
        external
        returns (uint256 amountOut);

    function quoteExactInput(bytes calldata path, uint256 amountIn)
        external
        returns (uint256 amountOut);
}
