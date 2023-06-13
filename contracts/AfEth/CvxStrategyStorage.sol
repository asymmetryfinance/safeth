// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../interfaces/IDerivative.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../interfaces/uniswap/ISwapRouter.sol";

/**
 @notice - Storage abstraction for CvxStrategy contract
 @dev - Upgradeability Rules:
        DO NOT change existing variable names or types
        DO NOT change order of variables
        DO NOT remove any variables
        ONLY add new variables at the end
        Constant values CAN be modified on upgrade
*/
contract CvxStrategyStorage {
    mapping(uint256 => uint256) public crvEmissionsPerYear;

    uint256 internal positionId;

    AggregatorV3Interface internal chainLinkCvxEthFeed;
    AggregatorV3Interface internal chainLinkCrvEthFeed;

    ISwapRouter internal swapRouter;

    address internal afEth;
    address internal crvPool;
    address internal safEth;

    struct Position {
        address owner; // owner of position
        uint256 curveBalance; // crv Pool LP amount
        uint256 afEthAmount; // afEth amount minted
        uint256 safEthAmount; // safEth amount minted
        uint256 createdAt; // block.timestamp
        bool claimed; // user has unstaked position
    }

    mapping(uint256 => Position) public positions;

    address lpTokenAddress;
    address lpRewardPoolAddress;
    address lpBoosterAddress;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
