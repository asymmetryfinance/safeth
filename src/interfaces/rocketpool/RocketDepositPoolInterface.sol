// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @dev Interface for RocketDepositPool
 * @dev See original implementation in official repository:
 * https://github.com/rocket-pool/rocketpool/blob/84e62846eb20d10a40978927fb50bc7f285c7fdd/contracts/interface/deposit/RocketDepositPoolInterface.sol
 */

interface RocketDepositPoolInterface {
    function getBalance() external view returns (uint256);

    function getExcessBalance() external view returns (uint256);

    function deposit() external payable;

    function recycleDissolvedDeposit() external payable;

    function recycleExcessCollateral() external payable;

    function recycleLiquidatedStake() external payable;

    function assignDeposits() external;

    function withdrawExcessBalance(uint256 _amount) external;
}
