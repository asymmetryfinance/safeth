// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "../src/StrategyGoldenRatio.sol";
import "../src/Vault.sol";
import "../src/Controller.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract StrategyTest is ERC1155Holder, Test {
    // rocketpoolstorage contract address: 0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46
    //Controller public controller;
    //controller = new Controller(address(0xABCD));
    //StrategyGoldenRatio private strat =new StrategyGoldenRatio(address(controller),0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46);

    //Vault public vault;
    //ERC20Mock public grETH;

    //address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    //IERC20 private cvx = IERC20(CVX);

    function setUp() public {
        //grETH = new ERC20Mock();
        //vault = new Vault(grETH, "Golden Ratio ETH", "grETH");
    }

    // function testVaultDeposit() public {}
    /*
    function testSwapAndLock() public {
        (bool sent, ) = address(strat).call{value: 1e18}("");
        require(sent, "Failed to send Ether");
        uint amountOut = strat.swapCvx();
        console.log("Amount Swapped:", amountOut);
        cvx.approve(address(this), amountOut);
        cvx.transferFrom(address(this), address(strat), amountOut);
        console.log(
            "Balance of CVX in strat contract after swap+transfer:",
            cvx.balanceOf(address(strat))
        );
        uint256 amountLocked = strat.lockCvx(amountOut);
        console.log("Locked balance:", amountLocked);
        uint256 amountMinted = strat.mintCvxNft(amountOut);
        console.log("Amount of CVX minted in 1155:", amountMinted);
    }

    function testDepositCrvPool() public {
        // send eth to contract depositing in crv pool
        (bool sent, ) = address(strat).call{value: 16e18}("");
        require(sent, "Failed to send Ether");
        strat.addCrvLiquidity();
    }
*/
    function testDepositREth() public {
        //strat.depositREth{value: 48e18}();
    }
    /*
    function testDepositWstEth() public {
        (bool sent, ) = address(strat).call{value: 1e18}("");
        require(sent, "Failed to send Ether");
        strat.depositWstEth();
    }
    */
    //function testVault() public {
    //vault.deposit{value: 1e18}(1e18, address(this));
    //    (bool sent, ) = address(vault).call{value: 1e18}("");
    //    require(sent, "Failed to send Ether");
    // }
}
