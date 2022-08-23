// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Oracle.sol";
import "../src/Vault.sol";

contract OracleTest is Test {
    Oracle public oracle;

    // Vault public vault;

    function setUp() public {
        oracle = new Oracle();
        // vault = new Vault();
    }

    function testOraclePair() public {
        int256 price = oracle.getLatestPrice();
        emit log_int(price);
    }

    function testDeposit() public {
        //uint256 depositAmount = 48 ether;
        // vault.deposit(depositAmount);
        // assertEq(depositAmount, 48000000000000000000);
        // emit log_uint(depositAmount);
    }
}
