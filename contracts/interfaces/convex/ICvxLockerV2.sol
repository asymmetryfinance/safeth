// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface ICvxLockerV2 {
    function lock(
        address _account,
        uint256 _amount,
        uint256 _spendRatio
    ) external;
}
