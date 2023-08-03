// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "../SafEth/derivatives/SfrxEth.sol";

/// @title Derivative contract for testing contract upgrades
/// @author Asymmetry Finance
contract SlippageFrax is SfrxEth {
    function setUnderlying(uint256 newUnderlying) public {
        underlyingBalance = newUnderlying;
    }
}
