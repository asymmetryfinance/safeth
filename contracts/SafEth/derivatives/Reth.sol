// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../interfaces/IDerivative.sol";
import "../../interfaces/frax/IsFrxEth.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/rocketpool/RocketStorageInterface.sol";
import "../../interfaces/rocketpool/RocketTokenRETHInterface.sol";
import "../../interfaces/rocketpool/RocketDepositPoolInterface.sol";
import "../../interfaces/rocketpool/RocketDAOProtocolSettingsDepositInterface.sol";
import "../../interfaces/IWETH.sol";
import "../../interfaces/uniswap/ISwapRouter.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../../interfaces/uniswap/IUniswapV3Factory.sol";
import "../../interfaces/uniswap/IUniswapV3Pool.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title Derivative contract for rETH
/// @author Asymmetry Finance
import "hardhat/console.sol";

contract Reth is IDerivative, Initializable, OwnableUpgradeable {
    address public constant ROCKET_STORAGE_ADDRESS =
        0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46;
    address public constant W_ETH_ADDRESS =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant UNISWAP_ROUTER =
        0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address public constant UNI_V3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    AggregatorV3Interface constant chainLinkRethEthFeed =
        AggregatorV3Interface(0x536218f9E9Eb48863970252233c8F271f554C2d0);

    uint256 public maxSlippage;

    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
        @notice - Function to initialize values for the contracts
        @dev - This replaces the constructor for upgradeable contracts
        @param _owner - owner of the contract which handles stake/unstake
    */
    function initialize(address _owner) external initializer {
        _transferOwnership(_owner);
        maxSlippage = (1 * 10 ** 16); // 1%
    }

    /**
        @notice - Return derivative name
    */
    function name() public pure returns (string memory) {
        return "RocketPool";
    }

    /**
        @notice - Owner only function to set max slippage for derivative
        @param _slippage - new slippage amount in wei
    */
    function setMaxSlippage(uint256 _slippage) external onlyOwner {
        maxSlippage = _slippage;
    }

    /**
        @notice - Get rETH address
        @dev - per RocketPool Docs query addresses each time it is used
     */
    function rethAddress() private view returns (address) {
        return
            RocketStorageInterface(ROCKET_STORAGE_ADDRESS).getAddress(
                keccak256(
                    abi.encodePacked("contract.address", "rocketTokenRETH")
                )
            );
    }

    /**
        @notice - Swap tokens through Uniswap
        @param _tokenIn - token to swap from
        @param _tokenOut - token to swap to
        @param _poolFee - pool fee for particular swap
        @param _amountIn - amount of token to swap from
        @param _minOut - minimum amount of token to receive (slippage)
     */
    function swapExactInputSingleHop(
        address _tokenIn,
        address _tokenOut,
        uint24 _poolFee,
        uint256 _amountIn,
        uint256 _minOut
    ) private returns (uint256 amountOut) {
        IERC20(_tokenIn).approve(UNISWAP_ROUTER, _amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: _poolFee,
                recipient: address(this),
                amountIn: _amountIn,
                amountOutMinimum: _minOut,
                sqrtPriceLimitX96: 0
            });
        amountOut = ISwapRouter(UNISWAP_ROUTER).exactInputSingle(params);
    }

    /**
        @notice - Convert derivative into ETH
     */
    function withdraw(uint256 amount) external onlyOwner {
        RocketTokenRETHInterface(rethAddress()).burn(amount);
        // solhint-disable-next-line
        (bool sent, ) = address(msg.sender).call{value: address(this).balance}(
            ""
        );
        require(sent, "Failed to send Ether");
    }

    /**
        @notice - Deposit into derivative
        @dev - will either get rETH on exchange or deposit into contract depending on availability
     */
    function deposit() external payable onlyOwner returns (uint256) {
        uint rethPerEth = (10 ** 36) / ethPerDerivative();

        uint256 minOut = ((((rethPerEth * msg.value) / 10 ** 18) *
            ((10 ** 18 - maxSlippage))) / 10 ** 18);

        IWETH(W_ETH_ADDRESS).deposit{value: msg.value}();
        uint256 amountSwapped = swapExactInputSingleHop(
            W_ETH_ADDRESS,
            rethAddress(),
            500,
            msg.value,
            minOut
        );

        return amountSwapped;
    }

    /**
        @notice - Get price of derivative in terms of ETH
     */
    function ethPerDerivative() public view returns (uint256) {
        (, int256 chainLinkRethEthPrice, , , ) = chainLinkRethEthFeed
            .latestRoundData();
        return uint256(chainLinkRethEthPrice);
    }

    /**
        @notice - Total derivative balance
     */
    function balance() public view returns (uint256) {
        return IERC20(rethAddress()).balanceOf(address(this));
    }

    receive() external payable {}
}
