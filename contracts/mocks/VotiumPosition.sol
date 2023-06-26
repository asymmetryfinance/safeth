// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "../interfaces/ISnapshotDelegationRegistry.sol";
import "../interfaces/convex/ILockedCvx.sol";
import "../interfaces/votium/IVotiumMerkleStash.sol";
import "../interfaces/convex/IClaimZap.sol";

contract VotiumPosition is Initializable, Ownable2StepUpgradeable {

    address private constant CVX_CLAIM_ZAP =
        0x3f29cB4111CbdA8081642DA1f75B3c12DECf2516;

    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        Ownable2StepUpgradeable.__Ownable2Step_init();
        _transferOwnership(msg.sender);
    }

    function setDelegate() external onlyOwner {
        bytes32 VotiumVoteDelegationId = 0x6376782e65746800000000000000000000000000000000000000000000000000;
        address DelegationRegistry = 0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446;
        ISnapshotDelegationRegistry(DelegationRegistry).setDelegate(
            VotiumVoteDelegationId,
            owner()
        );
    }

    function lockCvx(uint256 _amount) external onlyOwner {
        address CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        address VL_CVX = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;
        IERC20(CVX).approve(VL_CVX, _amount);
        ILockedCvx(VL_CVX).lock(address(this), _amount, 0);
    }

    function claimVotiumRewards(IVotiumMerkleStash.claimParam[] calldata claims) external onlyOwner {
        IVotiumMerkleStash(0x378Ba9B73309bE80BF4C2c027aAD799766a7ED5A).claimMulti(address(this), claims);
        // TODO convertreward tokens to eth
    }

    function claimVlcvxRewards() external onlyOwner {
        address[] memory emptyArray;
        IClaimZap(CVX_CLAIM_ZAP).claimRewards(
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
        // TODO convertreward tokens to eth
    }

    receive() external payable {}
}
