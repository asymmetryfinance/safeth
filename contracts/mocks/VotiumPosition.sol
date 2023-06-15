// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

contract VotiumPosition is Initializable, Ownable2StepUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        Ownable2StepUpgradeable.__Ownable2Step_init();
    }

    function doDelegation() external onlyOwner {}

    receive() external payable {}
}
