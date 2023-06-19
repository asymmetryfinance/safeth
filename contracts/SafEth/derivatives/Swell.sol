// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../interfaces/IDerivative.sol";
import "../../interfaces/balancer/IVault.sol";
import "../../interfaces/IWETH.sol";
import "../../interfaces/swell/ISwellEth.sol";
import "../../interfaces/uniswap/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Storage.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./DerivativeBase.sol";

/// @title Derivative contract for swETH
/// @author Asymmetry Finance
contract Swell is DerivativeBase {
    address private constant SWETH_ADDRESS =
        0xf951E335afb289353dc249e82926178EaC7DEd78;
    address private constant WETH_ADDRESS =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant UNISWAP_ROUTER =
        0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    uint256 public maxSlippage;
    uint256 public underlyingBalance;

    /**
        @notice - Function to initialize values for the contracts
        @dev - This replaces the constructor for upgradeable contracts
        @param _owner - owner of the contract which should be SafEth.sol
    */
    function initialize(address _owner) external initializer {
        super.init(_owner);
        maxSlippage = (1 * 1e16); // 1%
    }

    /**
        @notice - Return derivative name
    */
    function name() external pure returns (string memory) {
        return "Swell";
    }

    /**
        @notice - Owner only function to set max slippage for derivative
        @param _slippage - new slippage amount in wei
    */
    function setMaxSlippage(uint256 _slippage) external onlyManager {
        maxSlippage = _slippage;
    }

    /**
        @notice - Convert derivative into ETH
        @param _amount - amount of rETH to convert
     */
    function withdraw(uint256 _amount) external onlyOwner {
        uint256 ethBalanceBefore = address(this).balance;
        uint256 wethBalanceBefore = IERC20(WETH_ADDRESS).balanceOf(
            address(this)
        );
        swapInputSingle(_amount, SWETH_ADDRESS, WETH_ADDRESS);
        uint256 wethBalanceAfter = IERC20(WETH_ADDRESS).balanceOf(
            address(this)
        );
        IWETH(WETH_ADDRESS).withdraw(wethBalanceAfter - wethBalanceBefore);
        underlyingBalance = super.finalChecks(
            ethPerDerivative(true),
            _amount,
            maxSlippage,
            address(this).balance - ethBalanceBefore,
            false,
            underlyingBalance
        );
    }

    /**
        @notice - Deposit into sweth derivative
     */
    function deposit() external payable onlyOwner returns (uint256) {
        uint256 swethBalanceBefore = IERC20(SWETH_ADDRESS).balanceOf(
            address(this)
        );
        IWETH(WETH_ADDRESS).deposit{value: msg.value}();
        uint256 amount = IERC20(WETH_ADDRESS).balanceOf(address(this));
        swapInputSingle(amount, WETH_ADDRESS, SWETH_ADDRESS);
        uint256 received = IERC20(SWETH_ADDRESS).balanceOf(address(this)) -
            swethBalanceBefore;
        underlyingBalance = super.finalChecks(
            ethPerDerivative(true),
            msg.value,
            maxSlippage,
            received,
            true,
            underlyingBalance
        );
        return received;
    }

    /**
        @notice - Get price of derivative in terms of ETH
    */
    function ethPerDerivative(bool) public view returns (uint256) {
        return ISwellEth(SWETH_ADDRESS).swETHToETHRate();
    }

    /**
        @notice - Total derivative balance
     */
    function balance() external view returns (uint256) {
        return underlyingBalance;
    }

    function swapInputSingle(
        uint256 _amount,
        address _tokenIn,
        address _tokenOut
    ) internal {
        IERC20(_tokenIn).approve(UNISWAP_ROUTER, _amount);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: 500,
                recipient: address(this),
                amountIn: _amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        ISwapRouter(UNISWAP_ROUTER).exactInputSingle(params);
    }
}
