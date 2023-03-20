// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * https://etherscan.io/address/0x941eb6f616114e4ecaa85377945ea306002612fe#code#L1
 */
interface ICrvEthPool {
    function add_liquidity(
        uint256[2] memory amounts,
        uint256 min_mint_amount,
        bool use_eth
    ) external payable returns (uint256);

    function remove_liquidity(
        uint256 _amount,
        uint256[2] memory _min_amounts
    ) external;

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

    function get_dy(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256);

    function coins(uint256 index) external view returns (address);

    function price_oracle() external view returns (uint256);

    function get_virtual_price() external view returns (uint256);
}
