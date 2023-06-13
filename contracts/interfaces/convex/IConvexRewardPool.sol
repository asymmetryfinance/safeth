// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IConvexRewardPool {
    function getReward(address _account, bool _claimExtras) external;
}
