// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// Test re-entrancy on SafEth
import "../interfaces/ISafEth.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SafEthReentrancyTest {
    bool testReady;
    address safEthAddress;

    constructor(address _safEthAddress) {
        safEthAddress = _safEthAddress;
    }

    function testUnstake() public {
        testReady = true;
        ISafEth(safEthAddress).stake{value: 1 ether}();
        ISafEth(safEthAddress).unstake(
            IERC20(safEthAddress).balanceOf(address(this)) / 2
        );
    }

    receive() external payable {
        if (!testReady) return;
        testReady = false;
        ISafEth(safEthAddress).unstake(
            IERC20(safEthAddress).balanceOf(address(this)) / 2
        );
    }
}
