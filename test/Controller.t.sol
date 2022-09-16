// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ERC20Mock2} from "./mocks/ERC20Mock2.sol";
//import {Vault} from "../src/Vault.sol";
import {Controller} from "../src/Controller.sol";
import {StrategyGoldenRatio} from "../src/StrategyGoldenRatio.sol";

contract ControllerTest is Test {
    //Controller public controller;
    //ERC20Mock public testToken;
    //ERC20Mock2 public testToken2;
    //Vault public vault;
    //StrategyGoldenRatio public testStrategy;

    function setUp() public {
        //controller = new Controller(address(0xABCD));
        //testToken = new ERC20Mock();
        //testToken2 = new ERC20Mock2();
        //testStrategy = new StrategyGoldenRatio();
        //vault = new Vault(testToken, "MockERC20", "MOCK", address(controller));
    }
    /*
    function testSetVault() public {
        controller.setVault(address(testToken), address(vault));
        address vaultAddy = controller.vaults(address(testToken));
        console.log("goal vault to set: ", address(vault));
        console.log(
            "vault that actually got set: ",
            controller.vaults(address(testToken))
        );
        assertEq(vaultAddy, address(vault));
    }

    function testApproveAndSetStrategy() public {
        controller.approveStrategy(address(testToken), address(testStrategy));
        controller.setStrategy(address(testToken), address(testStrategy));
        console.log("goal strategy to set: ", address(testStrategy));
        console.log(
            "strategy that actually got set: ",
            controller.strategies(address(testToken))
        );
        assertEq(
            controller.strategies(address(testToken)),
            address(testStrategy)
        );
    }
*/
}
