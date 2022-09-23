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
import "../src/interfaces/lido/IWStETH.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import "../src/tokens/grETH.sol";

// maybe
//import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
//import "../interfaces/IStrategy.sol";

contract GoldenRatioTest is Test {
    address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant wStEthToken = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    IWStETH private wstEth = IWStETH(payable(wStEthToken));
    IERC20 private reth = IERC20(RETH);
    //ERC20 wethToken = ERC20Mock(WETH9);
    IWETH public weth = IWETH(WETH9);
    Controller public controller;
    Vault public vault;
    StrategyGoldenRatio public strategy;
    // test user account
    address constant alice = 0xD9f7F0b351A1e9EaF411fA8BEAa35E75355acaD6;
    grETH grETHToken;

    function setUp() public {
        grETHToken = new grETH("Golden Ratio ETH", "grETH", 18);
        // init new controller, vault, strategy
        controller = new Controller();
        vault = new Vault(
            WETH9,
            "Golden Ratio Vault",
            "grVault",
            msg.sender,
            address(controller)
        );
        strategy = new StrategyGoldenRatio(
            address(grETHToken),
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

    function testDeposit() public {
        console.log("Current Strategy:", strategy.getName());
        (bool sent, ) = address(alice).call{value: 48e18}("");
        require(sent, "Failed to send Ether");
        console.log("Alice depositing 48ETH into vault...");
        vm.prank(alice);
        vault._deposit{value: 48e18}();
        uint256 aliceMaxRedeem = vault.maxRedeem(address(alice));
        assertEq(aliceMaxRedeem, 48e18);
        address pool = strategy.getPool();
        // assertEq lp token balance after deposit and 32e18
        assertEq(IERC20(pool).balanceOf(address(strategy)), 32e18);
        console.log("Alice withdrawing 48ETH from vault...");
        vm.prank(alice);
        vault.withdraw(48e18, msg.sender, msg.sender);
        assertEq(IERC20(pool).balanceOf(address(strategy)), 0);
        assertEq(IERC20(address(grETHToken)).balanceOf(address(strategy)), 0);
    }
}
