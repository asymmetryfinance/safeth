// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../AfStrategy/AfStrategy.sol";
import "./AfStrategyV2MockStorage.sol";

contract AfStrategyV2Mock is AfStrategy, AfStrategyV2MockStorage {
    // test new function added for upgrade
    function newFunction() public {
        newFunctionCalled = true;
    }
}
