// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../SafEth/SafEth.sol";
import "./SafEthV2MockStorage.sol";

contract SafEthV2Mock is SafEth, SafEthV2MockStorage {
    // test new function added for upgrade
    function newFunction() public {
        newFunctionCalled = true;
    }
}
