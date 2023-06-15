// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "../interfaces/ISnapshotDelegationRegistry.sol";
import "../interfaces/convex/ILockedCvx.sol";

contract VotiumPosition is Initializable, Ownable2StepUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        Ownable2StepUpgradeable.__Ownable2Step_init();
    }

    function setDelegate() external onlyOwner {
        bytes32 vlCvxVoteDelegationId = 0x6376782e65746800000000000000000000000000000000000000000000000000;
        ISnapshotDelegationRegistry(0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446).setDelegate(
            vlCvxVoteDelegationId,
            owner()
        );
    }

    function lockCvx(uint256 _amount) external onlyOwner {
        IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B).approve(0x72a19342e8F1838460eBFCCEf09F6585e32db86E, _amount);
        ILockedCvx(0x72a19342e8F1838460eBFCCEf09F6585e32db86E).lock(address(this), _amount, 0);
    }

    receive() external payable {}
}
