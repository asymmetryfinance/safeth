// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract Controller is Test {
    Controller public controller;

    function setUp() public {
        //controller = new Controller;
    }

    function testSetVault() public {}
}
