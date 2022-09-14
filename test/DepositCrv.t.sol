// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/DepositCrv.sol";

// import "../src/StrategyGoldenRatio.sol";

contract DepositCrvTest is Test {
    DepositCrv private crv = new DepositCrv();

    function setUp() public {}

    function testDepositCrvPool() public {
        // send eth to contract depositing in crv pool
        (bool sent, ) = address(crv).call{value: 16e18}("");
        require(sent, "Failed to send Ether");
        crv.addLiquidity();
    }
}
