// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
//import "../src/GRWarden.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IWarden} from "../src/interfaces/warden/IWarden.sol";

//import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract WardenTest is Test {
    //GRWarden public warden;
    address constant wardenContract =
        0xA04A36614e4C1Eb8cc0137d6d34eaAc963167828;
    address public crvWhale = 0xe3997288987E6297Ad550A69B31439504F513267;
    address constant crvAddress = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    IERC20 private crv = IERC20(crvAddress);
    IWarden warden = IWarden(wardenContract);

    function setUp() public {}

    function buy(
        address delegator,
        address receiver,
        uint256 amount,
        uint256 duration
    ) public returns (uint256) {
        uint256 maxFeeAmount = warden.estimateFees(delegator, amount, 1);
        vm.prank(crvWhale);
        crv.approve(wardenContract, maxFeeAmount);
        console.log("allowance:", crv.allowance(crvWhale, wardenContract));
        vm.prank(crvWhale);
        uint256 wardenBuy = warden.buyDelegationBoost(
            delegator,
            receiver,
            amount,
            duration,
            maxFeeAmount
        );
        return (wardenBuy);
    }

    function testWardenBuy() public {
        // alice approve crv spend erc20
        //vm.prank(crvWhale);
        //crv.approve(address(this), 208375972672751355);
        //console.log("allowance:", crv.allowance(crvWhale, wardenMultiBuy));
        address delegator = 0xCC7AA155a408bb2f2f4C6273BE37Cd76ecdCDb04;
        address receiver = crvWhale;
        uint256 amount = 4037927043899255429091;
        uint256 duration = 1;
        vm.prank(crvWhale);
        uint256 result = buy(delegator, receiver, amount, duration);
        console.log("warden buy result:", result);
    }
}
