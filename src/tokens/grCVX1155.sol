// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract grCVX1155 is ERC1155("grCVXNFT") {
    function mint(
        uint256 id,
        uint256 amount,
        address recipient
    ) public {
        _mint(recipient, id, amount, "");
    }

    function burn(
        address from,
        uint256 id,
        uint256 amount
    ) public {
        _burn(from, id, amount);
    }
}
