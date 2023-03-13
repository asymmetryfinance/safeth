// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../interfaces/IDerivative.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/curve/ICrvEthPool.sol";
import "../../interfaces/lido/IWStETH.sol";

/// @title Derivative contract for wstETH
/// @author Asymmetry Finance
contract WstEth is IDerivative, Initializable, OwnableUpgradeable {
    address public constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant lidoCrvPool =
        0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address public constant stEthToken =
        0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

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
        maxSlippage = (5 * 10 ** 16); // 5%
    }

    /**
        @notice - Return derivative name
    */
    function name() public pure returns (string memory) {
        return "Lido";
    }

    /**
        @notice - Owner only function to set max slippage for derivative
    */
    function setMaxSlippage(uint256 _slippage) external onlyOwner {
        maxSlippage = _slippage;
    }

    /**
        @notice - Owner only function to Convert derivative into ETH
        @dev - Owner is set to afStrategy contract
     */
    function withdraw(uint256 _amount) external onlyOwner {
        IWStETH(wstETH).unwrap(_amount);
        uint256 stEthBal = IERC20(stEthToken).balanceOf(address(this));
        IERC20(stEthToken).approve(lidoCrvPool, stEthBal);
        uint256 minOut = (stEthBal * (10 ** 18 - maxSlippage)) / 10 ** 18;
        ICrvEthPool(lidoCrvPool).exchange(1, 0, stEthBal, minOut);
        (bool sent, ) = address(msg.sender).call{value: address(this).balance}(
            ""
        );
        require(sent, "Failed to send Ether");
    }

    /**
        @notice - Owner only function to Deposit ETH into derivative
        @dev - Owner is set to afStrategy contract
     */
    function deposit() external payable onlyOwner returns (uint256) {
        uint256 wstEthBalancePre = IWStETH(wstETH).balanceOf(address(this));

        (bool sent, ) = wstETH.call{value: msg.value}("");
        require(sent, "Failed to send Ether");
        uint256 wstEthBalancePost = IWStETH(wstETH).balanceOf(address(this));
        uint256 wstEthAmount = wstEthBalancePost - wstEthBalancePre;
        return (wstEthAmount);
    }

    /**
        @notice - Get price of derivative in terms of ETH
     */
    function ethPerDerivative(uint256 _amount) public view returns (uint256) {
        return IWStETH(wstETH).getStETHByWstETH(10 ** 18);
    }

    /**
        @notice - Total ETH value of derivative contract
     */
    function totalEthValue() external view returns (uint256) {
        return (ethPerDerivative(balance()) * balance()) / 10 ** 18;
    }

    /**
        @notice - Total derivative balance
     */
    function balance() public view returns (uint256) {
        return IERC20(wstETH).balanceOf(address(this));
    }

    receive() external payable {}
}
