// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IWarden} from "./interfaces/warden/IWarden.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import "forge-std/console.sol";

// user comes w/ <48 ETH
// ex. 1 ETH deposit
// 1 ETH -> vault -> allows fractionalized staking
// check box for renting liquidity
// cost to rent veCRV and duration -> 52 weeks
// cost to rent liquidity

contract GRWarden {
    address constant wardenContract =
        0xA04A36614e4C1Eb8cc0137d6d34eaAc963167828;
    address constant crvAddress = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    IERC20 private crv = IERC20(crvAddress);

    IWarden warden = IWarden(wardenContract);

    constructor() {}

    function buy(
        address delegator,
        address receiver,
        uint256 amount,
        uint256 duration
    ) public returns (uint256) {
        uint256 maxFeeAmount = warden.estimateFees(delegator, amount, 1);
        crv.approve(wardenContract, maxFeeAmount);
        console.log("allowance:", crv.allowance(address(this), wardenContract));
        uint256 wardenBuy = warden.buyDelegationBoost(
            delegator,
            receiver,
            amount,
            duration,
            maxFeeAmount
        );
        return (wardenBuy);
    }
}
