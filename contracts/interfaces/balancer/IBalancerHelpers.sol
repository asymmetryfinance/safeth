// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IVault.sol";

interface IBalancerHelpers {
    function queryExit(
        bytes32 poolId,
        address sender,
        address recipient,
        IVault.ExitPoolRequest memory request
    ) external returns (uint256 bptIn, uint256[] memory amountsOut);
}
