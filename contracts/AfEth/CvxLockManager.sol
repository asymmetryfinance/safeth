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
    uint256 constant cycleTime = 10368000; // 16 weeks

    struct CvxPosition {
        bool open;
        uint256 cvxAmount; // amount of cvx locked in this position
        uint256 cvxUnlockTime; // when the locked cvx can be withdrawn if the position is in closing state
    }

    mapping(uint256 => CvxPosition) public cvxPositions;

    // total cvx from closed positions we need to leave unlocked next cycle for users to withdraw
    uint256 cvxToLeaveUnlock;

    // When the user could receive their locked cvx if closing a position now
    // Remaining current cycle + 16 weeks.
    uint256 nextUnlockTime;

    // when relockCvx() should be called
    uint256 nextCycleStartTime;

    function openCvxPosition(uint256 cvxAmount, uint256 positionId) internal {
        cvxPositions[positionId].cvxAmount = cvxAmount;
        cvxPositions[positionId].open = true;
        IERC20(CVX).approve(vlCVX, cvxAmount);
        ILockedCvx(vlCVX).lock(address(this), cvxAmount, 0);
    }

    // Unlock and relock everything minus closed positions
    function relockCvx() public {
        require(block.timestamp > nextCycleStartTime, 'Cant relock yet');
        ILockedCvx(vlCVX).processExpiredLocks(false);
        uint256 cvxAmountToRelock = IERC20(CVX).balanceOf(address(this)) - cvxToLeaveUnlock;
        IERC20(CVX).approve(vlCVX, cvxAmountToRelock);
        ILockedCvx(vlCVX).lock(address(this), cvxAmountToRelock, 0);
        nextCycleStartTime = block.timestamp + cycleTime;
        nextUnlockTime = block.timestamp + (cycleTime * 2);
    }

    function requestCloseCvxPosition(uint256 positionId) public {
        require(cvxPositions[positionId].open == true, 'Not open');
        cvxPositions[positionId].open = false;
        cvxPositions[positionId].cvxUnlockTime = nextUnlockTime;
        cvxToLeaveUnlock += cvxPositions[positionId].cvxAmount;
    }

    // Withdraw cvx from a closed position
    function withdrawCvx(uint256 positionId) public {
        require(cvxPositions[positionId].open == false, 'Not closed');
        require(block.timestamp > cvxPositions[positionId].cvxUnlockTime, 'Cvx still locked');
        require(cvxPositions[positionId].cvxAmount > 0, 'No cvx to withdraw');
        cvxToLeaveUnlock -= cvxPositions[positionId].cvxAmount;
        IERC20(CVX).transfer(msg.sender, cvxPositions[positionId].cvxAmount);
        cvxPositions[positionId].cvxAmount = 0;
    }
}
