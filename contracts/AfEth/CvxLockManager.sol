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

import "hardhat/console.sol";

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

    function lockCvx(uint256 cvxAmount, uint256 positionId, address owner) internal {
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
        if(lastRelockEpoch == currentEpoch) return;

        (, uint256 unlockable,,) = ILockedCvx(vlCVX).lockedBalances(address(this));

        // nothing to unlock
        if(unlockable == 0) return;
        // unlock all
        ILockedCvx(vlCVX).processExpiredLocks(false);

        uint256 unlockedCvxBalance = IERC20(CVX).balanceOf(address(this));

        // nothing to relock
        if(unlockedCvxBalance == 0) return;

        uint256 toUnlock = 0;
        for(uint256 i=currentEpoch;i>lastRelockEpoch;i--) {
            toUnlock += unlockSchedule[i];
            unlockSchedule[i] = 0;
        }
        cvxToLeaveUnlocked += toUnlock;

        // relock everything minus unlocked obligations
        uint256 cvxAmountToRelock = unlockedCvxBalance - cvxToLeaveUnlocked;

        // nothing to relock
        if(cvxAmountToRelock == 0) return;

        IERC20(CVX).approve(vlCVX, cvxAmountToRelock);
        ILockedCvx(vlCVX).lock(address(this), cvxAmountToRelock, 0);

        lastRelockEpoch = currentEpoch;
    }

    function requestUnlockCvx(uint256 positionId, address owner) internal {
        require(cvxPositions[positionId].owner == owner, 'Not owner');
        require(cvxPositions[positionId].open == true, 'Not open');
        cvxPositions[positionId].open = false;

        uint256 currentEpoch = ILockedCvx(vlCVX).findEpochId(block.timestamp); 

        uint256 originalUnlockEpoch = cvxPositions[positionId].startingEpoch + 16;

        // when cvx is fully unlocked and can be withdrawn
        uint256 unlockEpoch;

        // position has never been relocked. original unlock epoch stands
        if(lastRelockEpoch < originalUnlockEpoch) unlockEpoch = originalUnlockEpoch;
        // position has been relocked since the originalUnlockEpoch passed
        // calculate what its new unlock epoch is
        else {
            uint256 epochDifference = currentEpoch - originalUnlockEpoch;
            uint256 lockLengthsSinceRelock = (epochDifference / 16) + 1;
            unlockEpoch = originalUnlockEpoch + lockLengthsSinceRelock * 16;
        }

        cvxPositions[positionId].unlockEpoch = unlockEpoch;
        unlockSchedule[unlockEpoch] += cvxPositions[positionId].cvxAmount;
    }

    // Try to withdraw cvx from a closed position
    function withdrawCvx(uint256 positionId) public {
        require(cvxPositions[positionId].startingEpoch > 0, 'Invalid positionId');
        require(cvxPositions[positionId].open == false, 'Not closed');

        // unlock and relock if havent yet for this epochCount
        // enusres there will be enough unlocked cvx to withdraw
        relockCvx();

        uint256 currentEpoch = ILockedCvx(vlCVX).findEpochId(block.timestamp); 

        require(currentEpoch >= cvxPositions[positionId].unlockEpoch, 'Cvx still locked');

        require(cvxPositions[positionId].cvxAmount > 0, 'No cvx to withdraw');
        cvxToLeaveUnlocked -= cvxPositions[positionId].cvxAmount;
        IERC20(CVX).transfer(cvxPositions[positionId].owner, cvxPositions[positionId].cvxAmount);
        cvxPositions[positionId].cvxAmount = 0;
    }
}
