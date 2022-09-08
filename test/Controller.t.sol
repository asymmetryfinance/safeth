// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ERC20Mock2} from "./mocks/ERC20Mock2.sol";
import {Vault} from "../src/Vault.sol";
import {Controller} from "../src/Controller.sol";
import {StrategyGoldenRatio} from "../src/StrategyGoldenRatio.sol";

contract ControllerTest is Test {
    Controller public controller;
    ERC20Mock public testToken;
    ERC20Mock2 public testToken2;
    Vault public vault;
    StrategyGoldenRatio public testStrategy;

    function setUp() public {
        controller = new Controller(address(0xABCD));
        testToken = new ERC20Mock();
        testToken2 = new ERC20Mock2();
        testStrategy = new StrategyGoldenRatio(
            address(testToken),
            address(testToken2)
        );
    }

    function testSetVault() public {}
}
