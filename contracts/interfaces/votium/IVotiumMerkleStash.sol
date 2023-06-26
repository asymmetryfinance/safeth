// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IVotiumMerkleStash {
    struct claimParam {
        address token;
        uint256 index;
        uint256 amount;
        bytes32[] merkleProof;
    }

    function claimMulti(address account, claimParam[] calldata claims) external;
}
