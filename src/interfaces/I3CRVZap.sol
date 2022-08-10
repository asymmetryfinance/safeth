// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface I3CRVZap {
    function add_liquidity(
        address _pool,
        uint256[4] calldata _deposit_amounts,
        uint256 _min_mint_amount
    ) external returns (uint256);
}
