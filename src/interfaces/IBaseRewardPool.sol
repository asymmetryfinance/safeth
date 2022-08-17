// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @dev Interface for
 * @dev See original implementation in official repository:
 * Link:
 */
interface IBaseRewardPool {
    function withdrawAndUnwrap(uint256 amount, bool claim)
        external
        returns (bool);

    function withdrawAllAndUnwrap(bool claim) external;

    function getReward(address _account, bool _claimExtras)
        external
        returns (bool);

    function donate(uint256 _amount) external returns (bool);

    function balanceOf(address) external view returns (uint256);

    function extraRewards(uint256) external view returns (address);

    function extraRewardsLength() external view returns (uint256);

    function rewardToken() external view returns (address);

    function earned(address account) external view returns (uint256);
}
