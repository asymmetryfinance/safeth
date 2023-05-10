// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/convex/ILockedCvx.sol";
import "../interfaces/convex/IClaimZap.sol";
import "../interfaces/curve/ICvxFxsFxsPool.sol";
import "../interfaces/curve/IFxsEthPool.sol";
import "../interfaces/curve/ICvxCrvCrvPool.sol";
import "../interfaces/curve/ICrvEthPool.sol";
import "../interfaces/ISnapshotDelegationRegistry.sol";
import "../interfaces/IExtraRewardsStream.sol";
import "./ExtraRewardsStream.sol";

import "hardhat/console.sol";

contract CvxLockManager is OwnableUpgradeable {
    address public constant SNAPSHOT_DELEGATE_REGISTRY =
        0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446;

    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant vlCVX = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;

    address public constant FXS_ETH_CRV_POOL_ADDRESS =
        0x941Eb6F616114e4Ecaa85377945EA306002612FE;
    address public constant CVXFXS_FXS_CRV_POOL_ADDRESS =
        0xd658A338613198204DCa1143Ac3F01A722b5d94A;
    address public constant CVXCRV_CRV_CRV_POOL_ADDRESS =
        0x9D0464996170c6B9e75eED71c68B99dDEDf279e8;
    address public constant CRV_ETH_CRV_POOL_ADDRESS =
        0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511;
    address public constant CVX_ETH_CRV_POOL_ADDRESS =
        0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4;

    address constant cvxClaimZap = 0x3f29cB4111CbdA8081642DA1f75B3c12DECf2516;

    address constant cvxCrv = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;
    address constant fxs = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    address constant crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address constant cvxFxs = 0xFEEf77d3f69374f66429C91d732A244f074bdf74;

    // last epoch in which relock was called
    uint256 public lastRelockEpoch;

    // cvx amount we cant relock because users have closed the positions and can now withdraw
    uint256 public cvxToLeaveUnlocked;

    // how much total rewards was claimed by the lock manager on each epoch
    mapping(uint256 => uint256) public rewardsClaimed;

    // what is the last epoch for which rewards have been fully claimed
    uint256 public lastEpochFullyClaimed;

    // rewards that were claimed but not in a completed epoch
    // they are included with the next call to claimRewards()
    uint256 public leftoverRewards;

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

    uint256 maxSlippage;

    address public extraRewardsStream;

    function initializeLockManager(address _extraRewardsStream) internal {
        bytes32 vlCvxVoteDelegationId = 0x6376782e65746800000000000000000000000000000000000000000000000000;
        ISnapshotDelegationRegistry(SNAPSHOT_DELEGATE_REGISTRY).setDelegate(
            vlCvxVoteDelegationId,
            owner()
        );

        lastRelockEpoch = ILockedCvx(vlCVX).findEpochId(block.timestamp);

        maxSlippage = 10 ** 16; // 1%
        uint256 currentEpoch = ILockedCvx(vlCVX).findEpochId(block.timestamp);
        if (lastEpochFullyClaimed == 0)
            lastEpochFullyClaimed = currentEpoch - 1;
        extraRewardsStream = _extraRewardsStream;
    }

    function setMaxSlippage(uint256 _maxSlippage) public onlyOwner {
        maxSlippage = _maxSlippage;
    }

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

    function sweepRewards() private {
        claimCrvRewards();
        claimvlCvxRewards();
        claimExtraRewards();
    }

    function claimExtraRewards() private {
        IExtraRewardsStream(extraRewardsStream).claim();
    }

    // claim vlCvx locker rewards and crv pool rewards
    // convert to eth and set claimed amounts for each epoch so we can what users are owed during withdraw
    function claimRewards() public {
        uint256 currentEpoch = ILockedCvx(vlCVX).findEpochId(block.timestamp);

        uint256 balanceBeforeClaim = address(this).balance;
        sweepRewards();
        uint256 balanceAfterClaim = address(this).balance;
        uint256 amountClaimed = (balanceAfterClaim - balanceBeforeClaim);
        // special case if claimRewards is called a second time in same epoch
        if (lastEpochFullyClaimed == currentEpoch - 1) {
            leftoverRewards += amountClaimed;
            return;
        }

        (
            uint256 _unused1,
            uint256 firstUnclaimedEpochStartingTime
        ) = ILockedCvx(vlCVX).epochs((lastEpochFullyClaimed + 1));
        (uint256 _unused2, uint256 currentEpochStartingTime) = ILockedCvx(vlCVX)
            .epochs(currentEpoch);

        // % of claimed rewards that go to the current (incomplete) epoch
        uint256 currentEpochRewardRatio = ((block.timestamp -
            currentEpochStartingTime) * 10 ** 18) /
            (block.timestamp - firstUnclaimedEpochStartingTime);

        // how much of the claimed rewards go to the current (incomplete) epoch
        uint256 currentEpochReward = (currentEpochRewardRatio * amountClaimed) /
            10 ** 18;

        uint256 completedEpochsRewardsOwed = (amountClaimed -
            currentEpochReward) + leftoverRewards;
        uint256 unclaimedCompletedEpochCount = currentEpoch -
            lastEpochFullyClaimed -
            1;

        uint256 rewardsPerCompletedEpoch = completedEpochsRewardsOwed /
            unclaimedCompletedEpochCount;

        for (uint256 i = lastEpochFullyClaimed + 1; i < currentEpoch; i++) {
            rewardsClaimed[i] = rewardsPerCompletedEpoch;
        }

        lastEpochFullyClaimed = currentEpoch - 1;
        leftoverRewards = currentEpochReward;
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
        if (currentEpoch >= originalUnlockEpoch) {
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
    function withdrawCvxAndRewards(uint256 positionId) public {
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
        // ensures there will be enough unlocked cvx to withdraw
        relockCvx();

        cvxToLeaveUnlocked -= cvxPositions[positionId].cvxAmount;
        require(
            IERC20(CVX).transfer(
                cvxPositions[positionId].owner,
                cvxPositions[positionId].cvxAmount
            ),
            "Couldn't transfer"
        );
        withdrawRewards(positionId);

        cvxPositions[positionId].cvxAmount = 0;
    }

    function getCurrentEpoch() public view returns (uint256) {
        return ILockedCvx(vlCVX).findEpochId(block.timestamp);
    }

    function withdrawRewards(uint256 positionId) private {
        uint256 currentEpoch = ILockedCvx(vlCVX).findEpochId(block.timestamp);

        // only claim rewards if needed
        if (lastEpochFullyClaimed < currentEpoch - 1) claimRewards();

        uint256 startingEpoch = cvxPositions[positionId].startingEpoch;
        uint256 positionAmount = cvxPositions[positionId].cvxAmount;
        uint256 unlockEpoch = cvxPositions[positionId].unlockEpoch;
        require(
            unlockEpoch != 0 && currentEpoch >= unlockEpoch,
            "Position still locked"
        );

        uint256 totalRewards = 0;

        // add up total rewards for a position up until unlock epoch -1
        for (uint256 i = startingEpoch; i < unlockEpoch; i++) {
            uint256 balanceAtEpoch = ILockedCvx(vlCVX).balanceAtEpochOf(
                i,
                address(this)
            );
            if (balanceAtEpoch == 0) continue;
            uint256 positionLockRatio = (positionAmount * 10 ** 18) /
                balanceAtEpoch;

            uint256 claimed = (positionLockRatio * rewardsClaimed[i]) /
                10 ** 18;
            totalRewards += claimed;
        }
        // solhint-disable-next-line
        (bool sent, ) = address(msg.sender).call{value: totalRewards}("");
        require(sent, "Failed to send Ether");
    }

    // TODO implement
    function claimCrvRewards() private {}

    // claim vlCvx rewards and convert to eth
    function claimvlCvxRewards() private {
        address[] memory emptyArray;
        IClaimZap(cvxClaimZap).claimRewards(
            emptyArray,
            emptyArray,
            emptyArray,
            emptyArray,
            0,
            0,
            0,
            0,
            8
        );
        // cvxFxs -> fxs
        uint256 cvxFxsBalance = IERC20(cvxFxs).balanceOf(address(this));
        if (cvxFxsBalance > 0) {
            uint256 oraclePrice = ICvxFxsFxsPool(CVXFXS_FXS_CRV_POOL_ADDRESS)
                .get_dy(1, 0, 10 ** 18);
            uint256 minOut = (((oraclePrice * cvxFxsBalance) / 10 ** 18) *
                (10 ** 18 - maxSlippage)) / 10 ** 18;

            IERC20(cvxFxs).approve(CVXFXS_FXS_CRV_POOL_ADDRESS, cvxFxsBalance);
            ICvxFxsFxsPool(CVXFXS_FXS_CRV_POOL_ADDRESS).exchange(
                1,
                0,
                cvxFxsBalance,
                minOut
            );
        }

        // fxs -> eth
        uint256 fxsBalance = IERC20(fxs).balanceOf(address(this));
        if (fxsBalance > 0) {
            uint256 oraclePrice = IFxsEthPool(FXS_ETH_CRV_POOL_ADDRESS).get_dy(
                1,
                0,
                10 ** 18
            );
            uint256 minOut = (((oraclePrice * fxsBalance) / 10 ** 18) *
                (10 ** 18 - maxSlippage)) / 10 ** 18;

            IERC20(fxs).approve(FXS_ETH_CRV_POOL_ADDRESS, fxsBalance);

            IERC20(fxs).allowance(address(this), FXS_ETH_CRV_POOL_ADDRESS);

            IFxsEthPool(FXS_ETH_CRV_POOL_ADDRESS).exchange_underlying(
                1,
                0,
                fxsBalance,
                minOut
            );
        }
        // cvxCrv -> crv
        uint256 cvxCrvBalance = IERC20(cvxCrv).balanceOf(address(this));
        if (cvxCrvBalance > 0) {
            uint256 oraclePrice = ICvxCrvCrvPool(CVXCRV_CRV_CRV_POOL_ADDRESS)
                .get_dy(1, 0, 10 ** 18);
            uint256 minOut = (((oraclePrice * cvxCrvBalance) / 10 ** 18) *
                (10 ** 18 - maxSlippage)) / 10 ** 18;
            IERC20(cvxCrv).approve(CVXCRV_CRV_CRV_POOL_ADDRESS, cvxCrvBalance);
            ICvxCrvCrvPool(CVXCRV_CRV_CRV_POOL_ADDRESS).exchange(
                1,
                0,
                cvxCrvBalance,
                minOut
            );
        }

        // crv -> eth
        uint256 crvBalance = IERC20(crv).balanceOf(address(this));
        if (crvBalance > 0) {
            uint256 oraclePrice = ICrvEthPool(CRV_ETH_CRV_POOL_ADDRESS).get_dy(
                1,
                0,
                10 ** 18
            );
            uint256 minOut = (((oraclePrice * crvBalance) / 10 ** 18) *
                (10 ** 18 - maxSlippage)) / 10 ** 18;

            IERC20(crv).approve(CRV_ETH_CRV_POOL_ADDRESS, crvBalance);
            ICrvEthPool(CRV_ETH_CRV_POOL_ADDRESS).exchange_underlying(
                1,
                0,
                crvBalance,
                minOut
            );
        }

        return;
    }
}
