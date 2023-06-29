// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./INftStrategy.sol";

/// For private internal functions and anything not exposed via the interface
contract VotiumStrategyCore is
    Initializable,
    OwnableUpgradeable,
    ERC1155Upgradeable
{
    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
        @notice - Function to initialize values for the contracts
        @dev - This replaces the constructor for upgradeable contracts
    */
    function initialize() external initializer {
        _transferOwnership(msg.sender);
    }

    receive() external payable {}

    error SwapFailed(uint256 index);

    struct SwapData {
        address sellToken;
        address buyToken;
        address spender;
        address swapTarget;
        bytes swapCallData;
    }

    /// sell any number of erc20's via 0x in a single tx
    function sellErc20s(
        SwapData[] calldata swapsData
    ) public onlyOwner returns (uint256 ethReceived) {
        uint256 ethBalanceBefore = address(this).balance;
        for (uint256 i = 0; i < swapsData.length; i++) {
            IERC20(swapsData[i].sellToken).approve(
                address(swapsData[i].spender),
                type(uint256).max
            );
            (bool success, ) = swapsData[i].swapTarget.call(
                swapsData[i].swapCallData
            );
            if (!success) revert SwapFailed(i);
        }
        uint256 ethBalanceAfter = address(this).balance;
        ethReceived = ethBalanceAfter - ethBalanceBefore;
    }
}
