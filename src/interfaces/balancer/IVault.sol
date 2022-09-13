// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../IERC20.sol";

interface IVault {
    function getPool(bytes32 poolId) external view returns (address);

    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (address tokens);
}
