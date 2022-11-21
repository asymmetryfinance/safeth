// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract grETH is ERC20 {
    address immutable MINTING_CONTRACT;

    constructor(
        address _mintingContract,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        MINTING_CONTRACT = _mintingContract;
    }

    function mint(address to, uint256 amount) public {
        require(msg.sender == MINTING_CONTRACT, "Must mint from contract");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        require(msg.sender == MINTING_CONTRACT, "Must burn from contract");
        _burn(from, amount);
    }
}
