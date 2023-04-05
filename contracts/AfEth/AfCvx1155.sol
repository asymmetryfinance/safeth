// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract AfCvx1155 is ERC1155("afCVXNFT") {
    address public MINTING_CONTRACT;

    // TODO: should change by governance
    function initialize(address _mintingContract) public {
        require(MINTING_CONTRACT == address(0), "Already initialized");
        require(_mintingContract != address(0), "Need valid address");
        MINTING_CONTRACT = _mintingContract;
    }

    function mint(address recipient, uint256 id, uint256 amount) public {
        require(msg.sender == MINTING_CONTRACT, "Must mint from contract");

        _mint(recipient, id, amount, "");
    }

    function burn(address from, uint256 id, uint256 amount) public {
        require(msg.sender == MINTING_CONTRACT, "Must burn from contract");
        _burn(from, id, amount);
    }
}
