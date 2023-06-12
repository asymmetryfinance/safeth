// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// Test re-entrancy on SafEth
import "../interfaces/ISafEth.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SafEthReentrancyTest {
    bool public testReady;
    address public safEthAddress;

    constructor(address _safEthAddress) {
        safEthAddress = _safEthAddress;
    }

    function testUnstake() public {
        testReady = true;
        ISafEth(safEthAddress).stake{value: 1 ether}(0);
        ISafEth(safEthAddress).unstake(
            IERC20(safEthAddress).balanceOf(address(this)) / 2,
            0
        );
    }

    receive() external payable {
        if (!testReady) return;
        testReady = false;
        ISafEth(safEthAddress).unstake(
            IERC20(safEthAddress).balanceOf(address(this)) / 2,
            0
        );
    }
}
