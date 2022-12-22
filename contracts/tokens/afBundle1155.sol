// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

// mints to strategy: cvxAmount to cvxNFTId, balLpAmount to BalNFTId
contract afBundle1155 is ERC1155("afBundleNFT") {
    address MINTING_CONTRACT;

    // TODO: should change by governance?
    function initialize(address _mintingContract) public {
        require(MINTING_CONTRACT == address(0), "Already initialized");
        require(_mintingContract != address(0), "Need valid address");
        MINTING_CONTRACT = _mintingContract;
    }

    function mint(
        uint256 cvxId,
        uint256 cvxAmount,
        uint256 balId,
        uint256 balAmount,
        address recipient
    ) public {
        require(msg.sender == MINTING_CONTRACT, "Must mint from contract");
        _mint(recipient, cvxId, cvxAmount, "");
        _mint(recipient, balId, balAmount, "");
    }

    //function burn() public {}
    function burnBatch(
        address from,
        uint256[2] memory ids,
        uint256[2] memory amounts
    ) public {
        require(msg.sender == MINTING_CONTRACT, "Must burn from contract");
        // burn bundle BPT balance
        _burn(from, ids[0], amounts[0]);
        // burn CVX NFT balance
        _burn(from, ids[1], amounts[1]);
    }
}
