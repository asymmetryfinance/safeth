// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {Vault} from "../src/Vault.sol";
import {Controller} from "../src/Controller.sol";
import {StrategyGoldenRatio} from "../src/StrategyGoldenRatio.sol";
import {IWStETH} from "../src/interfaces/lido/IWStETH.sol";
import {StETH4626} from "../src/Vaults/StETH4626.sol";
import {IStETH} from "../src/interfaces/lido/IStETH.sol";

contract VaultTest is Test {
    Controller public controller;
    ERC20Mock public testToken;
    Vault public vault;
    StrategyGoldenRatio public testStrategy;
    ERC20 constant underlying = stETH;
    IStETH constant stETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWStETH constant wstETH =
        IWStETH(payable(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0));
    StETH4626 public stEthVault;

    function setUp() public {
        controller = new Controller(address(0xABCD));
        testToken = new ERC20Mock();
        vault = new Vault(testToken, "MockERC20", "MOCK", address(controller));
        vm.label(address(wstETH), "wstETH");
        //testStrategy = new StrategyGoldenRatio();
        stEthVault = new StETH4626(underlying);
    }

    function mintUnderlying(address to, uint256 amount)
        internal
        returns (uint256)
    {
        uint256 wstETHAmount = wstETH.getWstETHByStETH(amount);
        deal(address(wstETH), to, wstETHAmount * 2);
        vm.prank(to);
        uint256 stETHAmount = wstETH.unwrap(wstETHAmount);
        return stETHAmount;
    }

    function testSingleDepositStEth() public {
        uint64 amount = 1e18;

        uint256 aliceUnderlyingAmount = amount;
        address alice = address(0xABCD);

        aliceUnderlyingAmount = mintUnderlying(alice, aliceUnderlyingAmount);
        vm.prank(alice);
        underlying.approve(address(stEthVault), aliceUnderlyingAmount);
        assertEq(
            underlying.allowance(alice, address(stEthVault)),
            aliceUnderlyingAmount
        );
        uint256 alicePreDepositBal = underlying.balanceOf(alice);
        console.log("alice pre dep bal: ", alicePreDepositBal);
        vm.prank(alice);
        //console.log("alice prev share amt: ", aliceShareAmount);
        uint256 aliceShareAmount = stEthVault.deposit(
            aliceUnderlyingAmount,
            alice
        );
        console.log("alice share amt: ", aliceShareAmount);
        assertGe(
            stEthVault.previewWithdraw(aliceUnderlyingAmount),
            aliceShareAmount,
            "previewWithdraw"
        );
        assertEq(
            stEthVault.previewDeposit(aliceUnderlyingAmount),
            aliceShareAmount,
            "previewDeposit"
        );
        console.log("stEthVault total supply:", stEthVault.totalSupply());
        assertEq(stEthVault.totalSupply(), aliceShareAmount, "totalSupply");
        assertGe(
            stEthVault.totalAssets(),
            aliceUnderlyingAmount - 2,
            "totalAssets"
        );
        assertLe(
            stEthVault.balanceOf(alice),
            aliceShareAmount,
            "stEthVault.balanceOf(alice)"
        );
        assertLe(
            stEthVault.convertToAssets(stEthVault.balanceOf(alice)),
            aliceUnderlyingAmount,
            "convertToAssets"
        );
        assertLe(
            underlying.balanceOf(alice),
            alicePreDepositBal + 2 - aliceUnderlyingAmount,
            "underlying.balanceOf(alice)"
        );

        aliceUnderlyingAmount = stEthVault.previewRedeem(
            stEthVault.balanceOf(alice)
        );
    }

    function testDepositEthIntoVault() public {
        address alice = address(0xDCBA);
        payable(alice).transfer(32 ether);
        //console.log("initial alice bal: ", address(alice).balance);
        //console.log("initial contract bal: ", address(vault).balance);
        vm.prank(alice);
        vault.depositEthIntoVault{value: 32 ether}(alice);
        //console.log("new contract bal: ", address(vault).balance);
        //console.log("new alice bal: ", address(alice).balance);
        assertEq(address(alice).balance, 0);
    }

    function testDepositEthForWstEth() public {
        address alice = address(0xDCBA);
        payable(alice).transfer(32 ether);
        vm.prank(alice);
        console.log("wstETH address", address(wstETH));
        console.log("balance before deposit", address(wstETH).balance);
        (bool sent, ) = address(wstETH).call{value: 1 ether}("");
        require(sent, "Failed to send Ether");
        console.log("balance after deposit", address(wstETH).balance);
        console.log(sent);
    }
}
