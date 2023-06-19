// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../interfaces/IDerivative.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/curve/IStEthEthPool.sol";
import "../../interfaces/lido/IWStETH.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Storage.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./DerivativeBase.sol";

/// @title Derivative contract for wstETH
/// @author Asymmetry Finance
contract WstEth is DerivativeBase {
    address private constant WST_ETH =
        0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address private constant LIDO_CRV_POOL =
        0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address private constant STETH_TOKEN =
        0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    // Deprecated
    AggregatorV3Interface internal constant CHAINLINK_STETH_ETH_FEED =
        AggregatorV3Interface(0x86392dC19c0b719886221c78AB11eb8Cf5c52812);

    uint256 public maxSlippage;
    uint256 public underlyingBalance;

    AggregatorV3Interface public chainlinkFeed;

    error NoStethToUnwrap();

    /**
        @notice - Function to initialize values for the contracts
        @dev - This replaces the constructor for upgradeable contracts
        @param _owner - owner of the contract which should be SafEth.sol
    */
    function initialize(address _owner) external initializer {
        super.init(_owner);
        maxSlippage = (1 * 1e16); // 1%
        chainlinkFeed = AggregatorV3Interface(
            0x86392dC19c0b719886221c78AB11eb8Cf5c52812
        );
    }

    /**
        @notice - Sets the address for the chainlink feed
        @param _priceFeedAddress - address of the chainlink feed
    */
    function setChainlinkFeed(address _priceFeedAddress) public onlyManager {
        chainlinkFeed = AggregatorV3Interface(_priceFeedAddress);
    }

    /**
        @notice - Return derivative name
    */
    function name() external pure returns (string memory) {
        return "Lido";
    }

    /**
        @notice - Owner only function to set max slippage for derivative
    */
    function setMaxSlippage(uint256 _slippage) external onlyManager {
        maxSlippage = _slippage;
    }

    /**
        @notice - Owner only function to Convert derivative into ETH
        @dev - Owner is set to SafEth contract
     */
    function withdraw(uint256 _amount) external onlyOwner {
        uint256 stEthAmount = IWStETH(WST_ETH).unwrap(_amount);
        if (stEthAmount == 0) revert NoStethToUnwrap();

        IERC20(STETH_TOKEN).approve(LIDO_CRV_POOL, stEthAmount);
        uint256 balancePre = address(this).balance;
        IStEthEthPool(LIDO_CRV_POOL).exchange(1, 0, stEthAmount, 0);
        underlyingBalance = super.finalChecks(
            ethPerDerivative(true),
            _amount,
            maxSlippage,
            address(this).balance - balancePre,
            false,
            underlyingBalance
        );
    }

    /**
        @notice - Owner only function to Deposit ETH into derivative
        @dev - Owner is set to SafEth contract
     */
    function deposit() external payable onlyOwner returns (uint256) {
        uint256 wstEthBalancePre = IWStETH(WST_ETH).balanceOf(address(this));
        // solhint-disable-next-line
        (bool sent, ) = WST_ETH.call{value: msg.value}("");
        if (!sent) revert FailedToSend();

        uint256 received = IWStETH(WST_ETH).balanceOf(address(this)) -
            wstEthBalancePre;
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
    function ethPerDerivative(bool _validate) public view returns (uint256) {
        ChainlinkResponse memory cl;
        try chainlinkFeed.latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256 /* startedAt */,
            uint256 updatedAt,
            uint80 /* answeredInRound */
        ) {
            cl.success = true;
            cl.roundId = roundId;
            cl.answer = answer;
            cl.updatedAt = updatedAt;
        } catch {
            if (!_validate) return 0;
            cl.success = false;
        }

        // verify chainlink response
        if (
            !_validate ||
            (cl.success == true &&
                cl.roundId != 0 &&
                cl.answer >= 0 &&
                cl.updatedAt != 0 &&
                cl.updatedAt <= block.timestamp &&
                block.timestamp - cl.updatedAt <= 25 hours)
        ) {
            uint256 stPerWst = IWStETH(WST_ETH).getStETHByWstETH(1e18);
            if (cl.answer < 0) cl.answer = 0;
            uint256 ethPerWstEth = (stPerWst * uint256(cl.answer)) / 1e18;
            return ethPerWstEth;
        } else {
            revert ChainlinkFailed("Wst");
        }
    }

    /**
        @notice - Total derivative balance
     */
    function balance() external view returns (uint256) {
        return underlyingBalance;
    }
}
