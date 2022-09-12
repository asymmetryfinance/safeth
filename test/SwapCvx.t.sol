// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/SwapCvx.sol";

address constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

contract SwapCvxTest is Test {
    IWETH private weth = IWETH(WETH9);
    IERC20 private cvx = IERC20(CVX);

    SwapCvx private swap = new SwapCvx();

    function setUp() public {}

    function testSingleHop() public {
        weth.deposit{value: 1e18}();
        weth.approve(address(swap), 1e18);

        uint amountOut = swap.swapExactInputSingleHop(WETH9, CVX, 10000, 1e18);

        uint256 amountInCVX = amountOut / 1e18;
        console.log("CVX", amountInCVX);
    }
}
