// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @dev Interface for EIP5115 Super Composable Yield Token
 * @dev See original implementation in official repository:
 * https://github.com/ethereum/EIPs/blob/master/EIPS/eip-5115.md
 */
interface ISuperComposableYield {
    enum AssetType {
        TOKEN,
        LIQUIDITY
    }

    event Deposit(
        address indexed caller,
        address indexed receiver,
        address indexed tokenIn,
        uint256 amountDeposited,
        uint256 amountScyOut
    );

    event Redeem(
        address indexed caller,
        address indexed receiver,
        address indexed tokenOut,
        uint256 amountScyToRedeem,
        uint256 amountTokenOut
    );

    event ClaimRewards(
        address indexed caller,
        address indexed user,
        address[] rewardTokens,
        uint256[] rewardAmounts
    );

    event ExchangeRateUpdated(uint256 oldExchangeRate, uint256 newExchangeRate);

    function deposit(
        address receiver,
        address tokenIn,
        uint256 amountTokenToPull,
        uint256 minSharesOut
    ) external returns (uint256 amountSharesOut);

    function redeem(
        address receiver,
        uint256 amountSharesToPull,
        address tokenOut,
        uint256 minTokenOut
    ) external returns (uint256 amountTokenOut);

    function claimRewards(address user)
        external
        returns (uint256[] memory rewardAmounts);

    function exchangeRateCurrent() external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function getRewardTokens() external view returns (address[] memory);

    function getBaseTokens() external view returns (address[] memory);

    function yieldToken() external view returns (address);

    function isValidBaseToken(address token) external view returns (bool);

    function assetInfo()
        external
        view
        returns (
            AssetType assetType,
            address assetAddress,
            uint8 assetDecimals
        );

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}
