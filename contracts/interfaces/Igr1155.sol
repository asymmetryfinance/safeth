// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface IgrCVX1155 is IERC1155 {
    function mint(
        uint256 id,
        uint256 amount,
        address recipient
    ) external;

    function burn(
        address from,
        uint256 id,
        uint256 amount
    ) external;
}

interface IgrBundle1155 is IERC1155 {
    function mint(
        uint256 cvxId,
        uint256 cvxAmount,
        uint256 balId,
        uint256 balAmount,
        address recipient
    ) external;

    function burnBatch(
        address from,
        uint256[2] memory ids,
        uint256[2] memory amounts
    ) external;
}
