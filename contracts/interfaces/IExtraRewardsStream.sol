// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IExtraRewardsStream {
    function reset(uint256 _duration, address _recipient) external;

    function claim() external;
}
