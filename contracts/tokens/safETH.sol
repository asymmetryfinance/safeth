// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SafETH is ERC20, Ownable {
    address public minter;

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {}

    function setMinter(address newMinter) public onlyOwner {
        minter = newMinter;
    }

    function mint(address to, uint256 amount) public {
        require(msg.sender == minter, "not minter");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        require(msg.sender == minter, "not minter");
        _burn(from, amount);
    }
}
