// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IConvexBooster {
    function depositAll(uint256 _pid, bool _stake) external;
}
