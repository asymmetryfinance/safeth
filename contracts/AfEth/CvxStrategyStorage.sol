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
    event UpdateCrvPool(address indexed newCrvPool, address oldCrvPool);
    event SetEmissionsPerYear(uint256 indexed year, uint256 emissions);
    event Staked(uint256 indexed position, address indexed user);
    event Unstaked(uint256 indexed position, address indexed user);

    error NotInitialized();
    error PositionClaimed();
    error NotOwner();
    error NotClosed();
    error NotOpen();
    error StillLocked();
    error NothingToWithdraw();
    error FailedToSend();
    error TransferFailed();
    error MustSeedPool();
    error InvalidPositionId();
    error NotEnough(string token);

    mapping(uint256 => uint256) public crvEmissionsPerYear;

    uint256 internal positionId;

    AggregatorV3Interface internal chainLinkCvxEthFeed;
    AggregatorV3Interface internal chainLinkCrvEthFeed;

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

    address private lpTokenAddress;
    address private lpRewardPoolAddress;
    address private lpBoosterAddress;

    address public constant CHAINLINK_CRV =
        0x8a12Be339B0cD1829b91Adc01977caa5E9ac121e;
    address public constant CHAINLINK_CVX =
        0xC9CbF687f43176B302F03f5e58470b77D07c61c6;
    address public constant SWAP_ROUTER =
        0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
