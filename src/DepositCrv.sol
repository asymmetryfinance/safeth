// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "./interfaces/curve/ICrvEthPool.sol";
import "./interfaces/curve/ICurve.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DepositCrv {
    //address private constant CURVE_3POOL_DEPOSIT_ZAP = 0xA79828DF1850E8a3A3064576f380D90aECDD3359;
    //address private constant stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address private constant stEthCrvPool =
        0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address private constant lpToken =
        0x06325440D014e39736583c165C2963BA99fAf14E;

    constructor() {}

    function addLiquidity() public {
        console.log("sender bal:", msg.sender.balance);
        console.log("this add bal:", address(this).balance);
        uint256[2] memory _amounts;
        _amounts = [uint256(1e18), 0];
        uint256 mintAmt = ICrvEthPool(stEthCrvPool).add_liquidity{
            value: _amounts[0]
        }(_amounts, 0);
        console.log("LP tokens minted:", mintAmt);
        uint256 lpMinted = IERC20(lpToken).balanceOf(address(this));
        console.log(lpMinted);
    }

    receive() external payable {}
}
