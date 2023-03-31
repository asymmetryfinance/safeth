// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

// mints to strategy: cvxAmount to cvxNFTId, balLpAmount to BalNFTId
contract afBundle1155 is ERC1155("afBundleNFT") {
    struct Position {
        uint256 created;
    }
    mapping(address => Position) position;
    address MINTING_CONTRACT;

    // TODO: should change by governance?
    function initialize(address _mintingContract) public {
        require(MINTING_CONTRACT == address(0), "Already initialized");
        require(_mintingContract != address(0), "Need valid address");
        MINTING_CONTRACT = _mintingContract;
    }

    function mint(address _recipient, uint256 _id, uint256 _amount) public {
        require(msg.sender == MINTING_CONTRACT, "Must mint from contract");
        _mint(_recipient, _id, _amount, "");
    }

    function burn(address _from, uint256 _id, uint256 _amount) public {
        require(msg.sender == MINTING_CONTRACT, "Must burn from contract");
        _burn(_from, _id, _amount);
    }
}
