// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @dev Interface for
 * @dev See original implementation in official repository:
 * Link:
 */
interface IBooster {
    function depositAll(uint256 _pid, bool _stake) external returns (bool);

    function earmarkRewards(uint256 _pid) external returns (bool);
}