// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract afETH is ERC20 {
    address MINTING_CONTRACT;

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {}

    // TODO: should change by governance?
    function initialize(address _mintingContract) public {
        require(MINTING_CONTRACT == address(0), "Already initialized");
        require(_mintingContract != address(0), "Need valid address");
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
