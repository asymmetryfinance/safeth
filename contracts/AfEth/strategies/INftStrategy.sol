// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface INftStrategy {
    /// open new position, returns positionId
    function mint() external payable returns (uint256);

    /// request to close a position
    function requestClose(uint256 positionId) external;

    /// check if a position has fully closed and can be burned
    function burnable(uint256 positionId) external view returns (uint256);

    /// burn token to claim eth if burnable(positionId) is true
    function burn(uint256 positionId) external;

    /// Withdraw any rewards from the position that can be claimed
    function claimRewards(uint256 positionId) external;

    /// how much rewards can be claimed right now
    function claimable(uint256 positionId) external view returns (uint256);

    /// how much has already been claimed from a position
    function claimed(uint256 positionId) external view returns (bool);

    /// current value of a position if it were to be burned right now
    function currentValue(uint256 positionId) external view returns (uint256);
}
