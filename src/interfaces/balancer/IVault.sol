// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../IERC20.sol";

interface IVault {
    /*
    function getPool(bytes32 poolId) external view returns (address);

    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (address tokens);
    */

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable;

    struct JoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    function exitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        ExitPoolRequest memory request
    ) external;

    struct ExitPoolRequest {
        address[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }
}
