// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.13;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";
// import {ERC20Mock} from "./mocks/ERC20Mock.sol";
// import {Vault} from "../src/Vault.sol";
// import "../src/StrategyGoldenRatio.sol";
// import {ERC20} from "solmate/tokens/ERC20.sol";
// import "../src/interfaces/IWETH.sol";

// contract VaultTest is Test {
//     /*
//     address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
//     ERC20 wethToken = ERC20Mock(WETH9);
//     IWETH private weth = IWETH(WETH9);
//     Vault public vault;
//     address public controller;
//     address public governance;
//     address constant alice = 0xD9f7F0b351A1e9EaF411fA8BEAa35E75355acaD6;
// */
//     //StrategyGoldenRatio private strategy =
//     //    new StrategyGoldenRatio(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46);

//     function setUp() public {
//         // underlying is WETH
//         //console.log("Deploying new vault with underlying WETH...");
//         //vault = new Vault(WETH9, "Golden Ratio Vault", "grVault");
//         //console.log("Vault Deployed");
//     }
//     /*
//     function testDepositWithdraw() public {
//         // send alice ether
//         (bool sent, ) = address(alice).call{value: 48e18}("");
//         require(sent, "Failed to send Ether");
//         console.log("Alice ETH Bal:", alice.balance);
//         console.log("Vault WETH Bal:", weth.balanceOf(address(vault)));
//         console.log("Vault eth post deposit bal", address(vault).balance);
//         // alice sends ether to vault
//         vm.prank(alice);
//         vault._deposit{value: 48e18}();
//         //console.log("alice share amount", aliceShareAmount);
//         console.log("Alice Post ETH Bal:", alice.balance);
//         console.log("Vault WETH Bal:", weth.balanceOf(address(vault)));
//         console.log("Alice WETH Bal:", weth.balanceOf(address(alice)));
//         console.log("Alice shares minted:", vault.getShares());
//         uint256 aliceMaxWithdraw = vault.maxWithdraw(address(alice));
//         console.log("Assets mapped to Alice:", aliceMaxWithdraw);
//         uint256 aliceMaxRedeem = vault.maxRedeem(address(alice));
//         console.log("Shares mapped to Alice:", aliceMaxRedeem);
//         console.log("Vault eth post deposit bal", address(vault).balance);
//     }
// */
// }
