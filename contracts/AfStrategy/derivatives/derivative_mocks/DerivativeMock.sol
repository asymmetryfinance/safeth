// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./IDerivativeMock.sol";
import "../../../interfaces/frax/IsFrxEth.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../interfaces/curve/ICrvEthPool.sol";
import "../../../interfaces/frax/IFrxETHMinter.sol";
import "hardhat/console.sol";

contract DerivativeMock is IDerivativeMock, Initializable, OwnableUpgradeable {
    address public constant sfrxEthAddress =
        0xac3E018457B222d93114458476f3E3416Abbe38F;
    address public constant frxEthAddress =
        0x5E8422345238F34275888049021821E8E08CAa1f;
    address public constant frxEthCrvPoolAddress =
        0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
    address public constant frxEthMinterAddress =
        0xbAFA44EFE7901E04E39Dad13167D089C559c1138;

    uint256 public maxSlippage;

    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setMaxSlippage(uint slippage) public onlyOwner {
        maxSlippage = slippage;
    }

    function withdrawAll() public onlyOwner {
        IsFrxEth(sfrxEthAddress).redeem(
            balance(),
            address(this),
            address(this)
        );
        uint256 frxEthBalance = IERC20(frxEthAddress).balanceOf(address(this));
        IsFrxEth(frxEthAddress).approve(frxEthCrvPoolAddress, frxEthBalance);
        // TODO figure out if we want a min receive amount and what it should be
        // Currently set to 0. It "works" but may not be ideal long term
        ICrvEthPool(frxEthCrvPoolAddress).exchange(1, 0, frxEthBalance, 0);
        (bool sent, ) = address(msg.sender).call{value: address(this).balance}(
            ""
        );
        require(sent, "Failed to send Ether");
    }

    function withdraw(uint256 amount) public onlyOwner {
        IsFrxEth(sfrxEthAddress).redeem(amount, address(this), address(this));
        uint256 frxEthBalance = IERC20(frxEthAddress).balanceOf(address(this));
        IsFrxEth(frxEthAddress).approve(frxEthCrvPoolAddress, frxEthBalance);

        uint256 minOut = (((ethPerDerivative(amount) * amount) / 10 ** 18) *
            (10 ** 18 - maxSlippage)) / 10 ** 18;

        ICrvEthPool(frxEthCrvPoolAddress).exchange(1, 0, frxEthBalance, minOut);
        (bool sent, ) = address(msg.sender).call{value: address(this).balance}(
            ""
        );
        require(sent, "Failed to send Ether");
    }

    function deposit() public payable onlyOwner returns (uint256) {
        IFrxETHMinter frxETHMinterContract = IFrxETHMinter(frxEthMinterAddress);
        uint256 sfrxBalancePre = IERC20(sfrxEthAddress).balanceOf(
            address(this)
        );
        frxETHMinterContract.submitAndDeposit{value: msg.value}(address(this));
        uint256 sfrxBalancePost = IERC20(sfrxEthAddress).balanceOf(
            address(this)
        );
        return sfrxBalancePost - sfrxBalancePre;
    }

    function ethPerDerivative(uint256 amount) public view returns (uint256) {
        uint256 frxAmount = IsFrxEth(sfrxEthAddress).convertToAssets(10 ** 18);
        return ((10 ** 18 * frxAmount) /
            ICrvEthPool(frxEthCrvPoolAddress).get_virtual_price());
    }

    function totalEthValue() public view returns (uint256) {
        return (ethPerDerivative(balance()) * balance()) / 10 ** 18;
    }

    function balance() public view returns (uint256) {
        return IERC20(sfrxEthAddress).balanceOf(address(this));
    }

    receive() external payable {}
}
