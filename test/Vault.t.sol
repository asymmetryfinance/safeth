// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Vault.sol";

contract VaultTest is Test {
    Vault public vault;

    function setUp() public {
        vault = new Vault();
    }

    function testDeposit() public {
        uint256 depositAmount = 48 ether;
        vault.deposit(depositAmount);
        emit log_uint(depositAmount);
    }
}
