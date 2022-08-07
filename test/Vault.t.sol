// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "./mocks/MockERC20.sol";

contract VaultTest is Test {
    Vault public vault;
    MockERC20 public mockToken;

    function setUp() public {
        vault = new Vault();
        mockToken = new MockERC20();
    }

    function testExample() public {
        uint256 amount = 10e18;
        mockToken.approve(address(vault), amount);
        bool vaultPassed = vault.stake(amount, address(mockToken));
        assertTrue(vaultPassed);
    }
}
