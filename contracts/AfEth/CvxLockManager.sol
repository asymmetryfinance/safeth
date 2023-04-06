// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/convex/ILockedCvx.sol";

contract CvxLockManager {
    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant vlCVX = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;

    // last epoch in which relock was called
    uint256 public lastRelockEpoch;

    // cvx amount we cant relock because users have closed the positions and can now withdraw
    uint256 public cvxToLeaveUnlocked;

    struct CvxPosition {
        address owner;
        bool open;
        uint256 cvxAmount; // amount of cvx locked in this position
        uint256 startingEpoch;
        uint256 unlockEpoch; // when they are expected to be able to withdraw (if relockCvx has been called)
    }

    mapping(uint256 => CvxPosition) public cvxPositions;

    // epoch at which amount should be unlocked
    mapping(uint256 => uint256) public unlockSchedule;

    function lockCvx(
        uint256 cvxAmount,
        uint256 positionId,
        address owner
    ) internal {
        uint256 currentEpoch = ILockedCvx(vlCVX).findEpochId(block.timestamp);

        cvxPositions[positionId].cvxAmount = cvxAmount;
        cvxPositions[positionId].open = true;
        cvxPositions[positionId].owner = owner;
        cvxPositions[positionId].startingEpoch = currentEpoch + 1;

        IERC20(CVX).approve(vlCVX, cvxAmount);
        ILockedCvx(vlCVX).lock(address(this), cvxAmount, 0);
    }

    // at the beginning of each new epoch to process the previous
    function relockCvx() public {
        uint256 currentEpoch = ILockedCvx(vlCVX).findEpochId(block.timestamp);
        // alredy called for this epoch
        if (lastRelockEpoch == currentEpoch) return;

        (, uint256 unlockable, , ) = ILockedCvx(vlCVX).lockedBalances(
            address(this)
        );

        // nothing to unlock
        if (unlockable == 0) return;
        // unlock all
        ILockedCvx(vlCVX).processExpiredLocks(false);

        uint256 unlockedCvxBalance = IERC20(CVX).balanceOf(address(this));

        // nothing to relock
        if (unlockedCvxBalance == 0) return;

        uint256 toUnlock = 0;
        // we overlap with the previous relock by 1 epoch
        // to make sure we dont miss any if they requested an unlock on the same epoch but after relockCvx() was called
        // TODO put more tests around this logic
        for (uint256 i = currentEpoch; i > lastRelockEpoch - 1; i--) {
            toUnlock += unlockSchedule[i];
            unlockSchedule[i] = 0;
        }
        cvxToLeaveUnlocked += toUnlock;

        // relock everything minus unlocked obligations
        uint256 cvxAmountToRelock = unlockedCvxBalance - cvxToLeaveUnlocked;

        // nothing to relock
        if (cvxAmountToRelock == 0) return;

        IERC20(CVX).approve(vlCVX, cvxAmountToRelock);
        ILockedCvx(vlCVX).lock(address(this), cvxAmountToRelock, 0);

        lastRelockEpoch = currentEpoch;
    }

    function requestUnlockCvx(uint256 positionId, address owner) internal {
        require(cvxPositions[positionId].owner == owner, "Not owner");
        require(cvxPositions[positionId].open == true, "Not open");
        cvxPositions[positionId].open = false;

        uint256 currentEpoch = ILockedCvx(vlCVX).findEpochId(block.timestamp);

        uint256 originalUnlockEpoch = cvxPositions[positionId].startingEpoch +
            16;

        // when cvx is fully unlocked and can be withdrawn
        uint256 unlockEpoch;

        // position has been relocked since the originalUnlockEpoch passed
        // calculate its new unlock epoch
        if (currentEpoch > originalUnlockEpoch) {
            uint256 epochDifference = currentEpoch - originalUnlockEpoch;
            uint256 extraLockLengths = (epochDifference / 16) + 1;
            unlockEpoch = originalUnlockEpoch + extraLockLengths * 16;
        } else {
            unlockEpoch = originalUnlockEpoch;
        }

        cvxPositions[positionId].unlockEpoch = unlockEpoch;
        unlockSchedule[unlockEpoch] += cvxPositions[positionId].cvxAmount;
    }

    // Try to withdraw cvx from a closed position
    function withdrawCvx(uint256 positionId) public {
        require(
            cvxPositions[positionId].startingEpoch > 0,
            "Invalid positionId"
        );
        require(cvxPositions[positionId].open == false, "Not closed");
        require(cvxPositions[positionId].cvxAmount > 0, "No cvx to withdraw");
        uint256 currentEpoch = ILockedCvx(vlCVX).findEpochId(block.timestamp);
        require(
            currentEpoch >= cvxPositions[positionId].unlockEpoch,
            "Cvx still locked"
        );

        // relock if havent yet for this epochCount
        // enusres there will be enough unlocked cvx to withdraw
        relockCvx();

        cvxToLeaveUnlocked -= cvxPositions[positionId].cvxAmount;
        require(
            IERC20(CVX).transfer(
                cvxPositions[positionId].owner,
                cvxPositions[positionId].cvxAmount
            ),
            "Couldnt transfer"
        );
        cvxPositions[positionId].cvxAmount = 0;
    }

    function getCurrentEpoch() public view returns (uint) {
        return ILockedCvx(vlCVX).findEpochId(block.timestamp);
    }
}
