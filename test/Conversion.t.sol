// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Oracle.sol";
import "../src/Vault.sol";

contract ConversionTest is Test {
    Conversion public conversion;
    Vault public vault;

    function setUp() public {
        conversion = new Conversion();
        vault = new Vault();
    }

    function testConversionPair() public {
        int256 price = conversion.getLatestPrice();
        emit log_int(price);
    }

    function testDeposit() public {
        uint256 depositAmount = 48 ether;
        vault.deposit(depositAmount);
        assertEq(depositAmount, 48000000000000000000);
        emit log_uint(depositAmount);
    }
}
