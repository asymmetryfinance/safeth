import "./VotiumStrategyCore.sol";
import "./INftStrategy.sol";

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract VotiumStrategy is VotiumStrategyCore, INftStrategy {
    function mint() external payable override returns (uint256) {}

    function requestClose(uint256 positionId) external override {}

    function burnable(
        uint256 positionId
    ) external view override returns (uint256) {}

    function burn(uint256 positionId) external override {}

    function claimRewards(uint256 positionId) external override {}

    function claimable(
        uint256 positionId
    ) external view override returns (uint256) {}

    function claimed(
        uint256 positionId
    ) external view override returns (bool) {}

    function currentValue(
        uint256 positionId
    ) external view override returns (uint256) {}
}
