// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract grBundle1155 is ERC1155("grBundleNFT") {
    function mint(
        uint256 cvxId,
        uint256 cvxAmount,
        uint256 balId,
        uint256 balAmount,
        address recipient
    ) public {
        _mint(recipient, cvxId, cvxAmount, "");
        _mint(recipient, balId, balAmount, "");
    }
}
