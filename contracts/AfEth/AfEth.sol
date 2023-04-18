// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// TODO: should we make this upgradeable?
contract AfEth is ERC20, Ownable {
    address public minter;

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {}

    function setMinter(address _newMinter) public onlyOwner {
        require(minter == address(0), "Already initialized");
        require(_newMinter != address(0), "Need valid address");
        minter = _newMinter;
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
