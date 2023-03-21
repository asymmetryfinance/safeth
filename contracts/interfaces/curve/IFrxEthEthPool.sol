// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IFrxEthEthPool {
    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external payable returns (uint256);

    function price_oracle() external view returns (uint256);

}
