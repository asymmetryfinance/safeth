// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// https://etherscan.io/address/0xb576491f1e6e5e62f1d8f26062ee822b40b0e0d4#code
interface ICvxEthPool {
    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 min_dy
    ) external payable returns (uint256);

    function exchange_underlying(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 min_dy
    ) external;

    function get_virtual_price() external view returns (uint256);

    function price_oracle() external view returns (uint256);

    function get_dy(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256);
}
