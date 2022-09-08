// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
//import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
//import {ERC20Mock2} from "./mocks/ERC20Mock2.sol";
import {Vault} from "../src/Vault.sol";
import {Controller} from "../src/Controller.sol";

contract VaultTest is Test {
    Controller public controller;
    ERC20Mock public testToken;
    Vault public vault;

    function setUp() public {
        controller = new Controller(address(0xABCD));
        testToken = new ERC20Mock();
        vault = new Vault(testToken, "MockERC20", "MOCK", address(controller));
    }

    function testDepositEthIntoVault() public {
        address alice = address(0xDCBA);
        payable(alice).transfer(32 ether);
        console.log("initial alice bal: ", address(alice).balance);
        console.log("initial contract bal: ", address(vault).balance);
        vm.prank(alice);
        vault.depositEthIntoVault{value: 32 ether}(alice);
        console.log("new contract bal: ", address(vault).balance);
        console.log("new alice bal: ", address(alice).balance);
        assertEq(address(alice).balance, 0);
    }
}
