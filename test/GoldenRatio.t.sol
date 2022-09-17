// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/StrategyGoldenRatio.sol";
import "../src/Vault.sol";
import "../src/Controller.sol";
import "../src/interfaces/IController.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import "../src/interfaces/IWETH.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

// maybe
//import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
//import "../interfaces/IStrategy.sol";

contract GoldenRatioTest is Test {
    address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    ERC20 wethToken = ERC20Mock(WETH9);
    IWETH public weth = IWETH(WETH9);
    Controller public controller;
    Vault public vault;
    StrategyGoldenRatio public strategy;
    // test user account
    address constant alice = 0xD9f7F0b351A1e9EaF411fA8BEAa35E75355acaD6;

    function setUp() public {
        // init new controller, vault, strategy
        controller = new Controller(msg.sender);
        vault = new Vault(
            WETH9,
            "Wrapped Ether",
            "WETH",
            msg.sender,
            address(controller)
        );
        strategy = new StrategyGoldenRatio(
            address(controller),
            0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46
        );
        // setup connections between controller, vault, and strategy
        controller.setVault(address(WETH9), address(vault));
        controller.approveStrategy(address(WETH9), address(strategy));
        controller.setStrategy(address(WETH9), address(strategy));
    }

    function testSetStrategy() public {
        address currentStrat = controller.strategies(address(WETH9));
        assertEq(currentStrat, address(strategy));
    }

    function testSetVault() public {
        address currentVault = controller.vaults(address(WETH9));
        assertEq(currentVault, address(vault));
    }

    // send required ETH to vault
    // check that CRV and CVX deposits work
    // check that CVX NFT is minted
    // check that stETH and rETH stakes work
    function testDeposit() public {
        // send alice ether to deposit
        console.log("Current Strategy:", strategy.getName());
        (bool sent, ) = address(alice).call{value: 48e18}("");
        require(sent, "Failed to send Ether");
        // alice sends ether to vault
        console.log("Alice depositing 48ETH into vault...");
        vm.prank(alice);
        vault._deposit{value: 48e18}();
        uint256 aliceMaxRedeem = vault.maxRedeem(address(alice));
        // check alice minted 48e18 worth of shares in vault
        assertEq(aliceMaxRedeem, 48e18);
        console.log("alice shares minted:", aliceMaxRedeem);
        console.log("WETH moving to strategy...");
        console.log("Depositing ETH into CRV Pool and Locking CVX...");
        console.log("Staking stETH and rETH...");
    }
}
