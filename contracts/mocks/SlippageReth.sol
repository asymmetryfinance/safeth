// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "../SafEth/derivatives/Reth.sol";

/// @title Derivative contract for testing contract upgrades
/// @author Asymmetry Finance
contract SlippageReth is Reth {
    function setUnderlying(uint256 newUnderlying) public {
        underlyingBalance = newUnderlying;
    }
}
