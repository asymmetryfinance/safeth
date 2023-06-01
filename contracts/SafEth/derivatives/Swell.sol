// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../interfaces/IDerivative.sol";
import "../../interfaces/balancer/IVault.sol";
import "../../interfaces/IWETH.sol";
import "../../interfaces/swell/ISwellEth.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Storage.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title Derivative contract for swETH
/// @author Asymmetry Finance
contract Swell is
    ERC165Storage,
    IDerivative,
    Initializable,
    OwnableUpgradeable
{
    address private constant SWETH_ADDRESS =
        0xf951E335afb289353dc249e82926178EaC7DEd78;
    address private constant W_ETH_ADDRESS =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IVault public constant balancerVault =
        IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    address constant wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 public maxSlippage;
    uint256 public underlyingBalance;

    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
        @notice - Function to initialize values for the contracts
        @dev - This replaces the constructor for upgradeable contracts
        @param _owner - owner of the contract which should be SafEth.sol
    */
    function initialize(address _owner) external initializer {
        require(_owner != address(0), "invalid address");
        _registerInterface(type(IDerivative).interfaceId);
        _transferOwnership(_owner);
        maxSlippage = (1 * 1e16); // 1%
    }

    function setChainlinkFeed(address _priceFeedAddress) public onlyOwner {
        // noop
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
    function setMaxSlippage(uint256 _slippage) external onlyOwner {
        maxSlippage = _slippage;
    }

    /**
        @notice - Convert derivative into ETH
        @param _amount - amount of rETH to convert
     */
    function withdraw(uint256 _amount) external onlyOwner {
        underlyingBalance = underlyingBalance - _amount;
        uint256 ethBalanceBefore = address(this).balance;
        uint256 wethBalanceBefore = IERC20(W_ETH_ADDRESS).balanceOf(
            address(this)
        );
        uint256 ethPerReth = ethPerDerivative();
        uint256 minOut = ((ethPerReth * _amount) * (1e18 - maxSlippage)) / 1e36;
        uint256 idealOut = ((ethPerReth * _amount) / 1e18);
        balancerSwap(idealOut, minOut);
        uint256 wethBalanceAfter = IERC20(W_ETH_ADDRESS).balanceOf(
            address(this)
        );
        IWETH(W_ETH_ADDRESS).withdraw(wethBalanceAfter - wethBalanceBefore);
        // solhint-disable-next-line
        uint256 ethBalanceAfter = address(this).balance;
        uint256 ethReceived = ethBalanceAfter - ethBalanceBefore;
        (bool sent, ) = address(msg.sender).call{value: ethReceived}("");
        require(sent, "Failed to send Ether");
    }

    /**
        @notice - Deposit into reth derivative
     */
    function deposit() external payable onlyOwner returns (uint256) {
        // uint256 minOut = (msg.value * (1e18 - maxSlippage)) /
        //     ethPerDerivative();
        uint256 swethBalanceBefore = IERC20(SWETH_ADDRESS).balanceOf(
            address(this)
        );
        ISwellEth(SWETH_ADDRESS).deposit{value: msg.value}();
        uint256 swethBalanceAfter = IERC20(SWETH_ADDRESS).balanceOf(
            address(this)
        );
        uint256 amountSwapped = swethBalanceAfter - swethBalanceBefore;
        underlyingBalance = underlyingBalance + amountSwapped;
        return amountSwapped;
    }

    /**
        @notice - Get price of derivative in terms of ETH
     */
    function ethPerDerivative() public view returns (uint256) {
        return ISwellEth(SWETH_ADDRESS).swETHToETHRate();
    }

    /**
        @notice - Total derivative balance
     */
    function balance() external view returns (uint256) {
        return underlyingBalance;
    }

    function balancerSwap(uint256 _amount, uint256 _minOut) private {
        if (_amount == 0) {
            return;
        }
        IVault.SingleSwap memory swap;
        swap
            .poolId = 0x1e19cf2d73a72ef1332c882f20534b6519be0276000200000000000000000112;
        swap.kind = IVault.SwapKind.GIVEN_IN;
        swap.assetOut = address(W_ETH_ADDRESS);
        swap.assetIn = address(SWETH_ADDRESS);
        swap.amount = _amount;

        IVault.FundManagement memory fundManagement;
        fundManagement.sender = address(this);
        fundManagement.recipient = address(this);
        fundManagement.fromInternalBalance = false;
        fundManagement.toInternalBalance = false;

        IWETH(wETH).deposit{value: _amount}();
        IERC20(W_ETH_ADDRESS).approve(address(balancerVault), _amount);
        // Execute swap
        balancerVault.swap(swap, fundManagement, _minOut, block.timestamp);
    }

    receive() external payable {}
}
