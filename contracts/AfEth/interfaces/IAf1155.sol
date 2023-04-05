// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface IAf1155 is IERC1155 {
    function mint(address recipient, uint256 id, uint256 amount) external;

    function burn(address from, uint256 id, uint256 amount) external;
}
