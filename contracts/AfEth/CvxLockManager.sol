// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../interfaces/uniswap/ISwapRouter.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/ISnapshotDelegationRegistry.sol";
import "./interfaces/convex/ILockedCvx.sol";
import "./interfaces/convex/IClaimZap.sol";
import "../interfaces/curve/ICvxCrvCrvPool.sol";
import "../interfaces/curve/IFxsEthPool.sol";
import "../interfaces/curve/ICrvEthPool.sol";
import "../interfaces/curve/ICvxFxsFxsPool.sol";
import "../interfaces/curve/IAfEthPool.sol";
import "./interfaces/IAf1155.sol";
import "./interfaces/ISafEth.sol";

contract CvxLockManager {
    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant vlCVX = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;

    // We assume a relock will be called at least once a week
    // Less often could lead to users not being able to withdraw when they expect
    uint256 constant minimumRelockInterval = 60 * 60 * 24 * 7; // 1 week

    uint256 constant cvxLockLength = 60 * 60 * 24 * 7 * 16; // 16 weeks

    // to know if we force the user to pay gas for relocking
    uint256 public lastRelockTime;

    // total cvx we need unlocked for users to withdraw after closing a position
    uint256 public cvxToLeaveUnlocked;

    struct CvxPosition {
        address owner;
        bool open;
        uint256 cvxAmount; // amount of cvx locked in this position
        uint256 unlockWeek; // week the funds can be unlocked if position is closed
    }

    mapping(uint256 => CvxPosition) public cvxPositions;

    // week to unlockAmount
    mapping(uint256 => uint256) public unlockSchedule;

    function getCurrentWeek() public view returns (uint256) {
        return (block.timestamp / minimumRelockInterval);
    }

    function getWeek(uint256 timestamp) public pure returns (uint256) {
        return timestamp / minimumRelockInterval;
    }

    function lockCvx(uint256 cvxAmount, uint256 positionId, address owner) internal {
        cvxPositions[positionId].cvxAmount = cvxAmount;
        cvxPositions[positionId].open = true;
        cvxPositions[positionId].owner = owner;
        IERC20(CVX).approve(vlCVX, cvxAmount);
        ILockedCvx(vlCVX).lock(address(this), cvxAmount, 0);
    }

    // intended to be called every minimumRelockInterval (1 week)
    function relockCvxIfnNeeded() public {
        uint256 currentWeek = getCurrentWeek();
        uint256 lastWeekRelocked = getWeek(lastRelockTime);
        // already relocked everything through this week
        if(lastWeekRelocked == currentWeek) return;

        // add up the amount we need to unlock between current week and last time this was called
        uint256 amountToUnlock = 0;
        for(uint256 i=currentWeek;i>lastWeekRelocked;i--) {
            amountToUnlock += unlockSchedule[i];
            unlockSchedule[i] = 0;
        }

        // nothing to unlock/relock since last time
        if(amountToUnlock == 0) return;

        // unlock all
        ILockedCvx(vlCVX).processExpiredLocks(false);

        uint256 unlockedCvxBalance = IERC20(CVX).balanceOf(address(this));

        cvxToLeaveUnlocked += amountToUnlock;

        // relock everything minus unlocked obligations
        uint256 cvxAmountToRelock = unlockedCvxBalance - cvxToLeaveUnlocked;

        if(cvxAmountToRelock == 0) return;

        IERC20(CVX).approve(vlCVX, cvxAmountToRelock); // possible gas optimization only calling approve once with max value
        ILockedCvx(vlCVX).lock(address(this), cvxAmountToRelock, 0);

        lastRelockTime = block.timestamp;
    }

    function requestUnlockCvx(uint256 positionId, address owner) internal {
        require(cvxPositions[positionId].owner == owner, 'Not owner');
        require(cvxPositions[positionId].open == true, 'Not open');
        cvxPositions[positionId].open = false;
        cvxPositions[positionId].unlockWeek = getCurrentWeek() + 17;
        unlockSchedule[cvxPositions[positionId].unlockWeek] += cvxPositions[positionId].cvxAmount;
    }

    // Try to withdraw cvx from a closed position
    function withdrawCvx(uint256 positionId) public {
        require(cvxPositions[positionId].open == false, 'Not closed');

        require(getCurrentWeek() >= cvxPositions[positionId].unlockWeek, 'Cvx still locked');
        require(cvxPositions[positionId].cvxAmount > 0, 'No cvx to withdraw');

        // Not enough unlocked cvx balance
        // lockCvxIfneeded must not have been called yet for the current week
        if(cvxPositions[positionId].cvxAmount > IERC20(CVX).balanceOf(address(this))) relockCvxIfnNeeded();

        cvxToLeaveUnlocked -= cvxPositions[positionId].cvxAmount;
        IERC20(CVX).transfer(cvxPositions[positionId].owner, cvxPositions[positionId].cvxAmount);
        cvxPositions[positionId].cvxAmount = 0;
    }
}
