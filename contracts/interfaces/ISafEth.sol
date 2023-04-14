// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface ISafEth {
    function stake() external payable returns (uint256);

    function unstake(uint256 _safEthAmount) external;
}
