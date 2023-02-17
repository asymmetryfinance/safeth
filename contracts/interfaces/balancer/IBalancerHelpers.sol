// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IBalancerVault.sol";

interface IBalancerHelpers {
    function queryExit(
        bytes32 poolId,
        address sender,
        address recipient,
        IBalancerVault.ExitPoolRequest memory request
    ) external returns (uint256 bptIn, uint256[] memory amountsOut);
}
