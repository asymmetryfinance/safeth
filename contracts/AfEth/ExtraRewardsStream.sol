// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "hardhat/console.sol";

contract ExtraRewardsStream {
    uint256 public totalAmount;
    uint256 public duration;
    uint256 public startTime;
    uint256 public claimedAmount;
    address public recipient;

    // Send this contract some eth to fund the extra rewards
    // then call resetExtraRewards to initialize
    function reset(uint256 _duration, address _recipient) public {
        duration = _duration;
        totalAmount = address(this).balance;
        startTime = block.timestamp;
        claimedAmount = 0;
        recipient = _recipient;
    }

    function claim() public {
        uint256 elapsedTime = block.timestamp - startTime;
        uint256 amount = ((totalAmount * elapsedTime) / duration) -
            claimedAmount;
        if (amount > address(this).balance) amount = address(this).balance;
        claimedAmount += amount;
        payable(recipient).transfer(amount);
    }

    receive() external payable {}
}
