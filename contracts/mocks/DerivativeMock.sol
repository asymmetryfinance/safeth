// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./IDerivativeMock.sol";
import "../interfaces/frax/IsFrxEth.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/curve/IFrxEthEthPool.sol";
import "../SafEth/derivatives/SfrxEth.sol";

/// @title Derivative contract for testing contract upgrades
/// @author Asymmetry Finance
contract DerivativeMock is SfrxEth {
    address private constant SFRX_ETH_ADDRESS =
        0xac3E018457B222d93114458476f3E3416Abbe38F;
    address private constant FRX_ETH_ADDRESS =
        0x5E8422345238F34275888049021821E8E08CAa1f;
    address private constant FRX_ETH_CRV_POOL_ADDRESS =
        0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
    address private constant FRX_ETH_MINTER_ADDRESS =
        0xbAFA44EFE7901E04E39Dad13167D089C559c1138;

    /**
        @notice - New function to test upgrading a contract and using new functionality
        */
    function withdrawAll() public onlyOwner {
        IsFrxEth(SFRX_ETH_ADDRESS).redeem(
            balance(),
            address(this),
            address(this)
        );
        uint256 frxEthBalance = IERC20(FRX_ETH_ADDRESS).balanceOf(
            address(this)
        );
        IsFrxEth(FRX_ETH_ADDRESS).approve(
            FRX_ETH_CRV_POOL_ADDRESS,
            frxEthBalance
        );
        IFrxEthEthPool(FRX_ETH_CRV_POOL_ADDRESS).exchange(
            1,
            0,
            frxEthBalance,
            0
        );
        // solhint-disable-next-line
        (bool sent, ) = address(msg.sender).call{value: address(this).balance}(
            ""
        );
        if (!sent) revert FailedToSend();
    }
}
