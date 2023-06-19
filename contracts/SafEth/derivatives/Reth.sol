// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../interfaces/IDerivative.sol";
import "../../interfaces/rocketpool/RocketStorageInterface.sol";
import "../../interfaces/rocketpool/RocketTokenRETHInterface.sol";
import "../../interfaces/rocketpool/RocketDepositPoolInterface.sol";
import "../../interfaces/rocketpool/RocketSwapRouterInterface.sol";
import "../../interfaces/balancer/IVault.sol";
import "../../interfaces/IWETH.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Storage.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./DerivativeBase.sol";

/// @title Derivative contract for rETH
/// @author Asymmetry Finance
contract Reth is DerivativeBase {
    address private constant ROCKET_STORAGE_ADDRESS =
        0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46;
    address private constant W_ETH_ADDRESS =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant UNISWAP_ROUTER =
        0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address private constant UNI_V3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    /// Swap router is not available in rocket storage contract so we hardcode it
    /// https://docs.rocketpool.net/developers/usage/contracts/contracts.html#interacting-with-rocket-pool
    address public constant ROCKET_SWAP_ROUTER =
        0x16D5A408e807db8eF7c578279BEeEe6b228f1c1C;

    // Deprecated
    AggregatorV3Interface internal constant CHAINLINK_RETH_ETH_FEED =
        AggregatorV3Interface(0x536218f9E9Eb48863970252233c8F271f554C2d0);

    uint256 public maxSlippage;
    uint256 public underlyingBalance;

    IVault public constant BALANCER_VAULT =
        IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    AggregatorV3Interface public chainlinkFeed;

    /**
        @notice - Function to initialize values for the contracts
        @dev - This replaces the constructor for upgradeable contracts
        @param _owner - owner of the contract which should be SafEth.sol
    */
    function initialize(address _owner) external initializer {
        super.init(_owner);
        maxSlippage = (1 * 1e16); // 1%
        chainlinkFeed = AggregatorV3Interface(
            0x536218f9E9Eb48863970252233c8F271f554C2d0
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
        return "RocketPool";
    }

    /**
        @notice - Owner only function to set max slippage for derivative
        @param _slippage - new slippage amount in wei
    */
    function setMaxSlippage(uint256 _slippage) external onlyManager {
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
        @notice - Convert derivative into ETH
        @param _amount - amount of rETH to convert
     */
    function withdraw(uint256 _amount) external onlyOwner {
        uint256 ethBalanceBefore = address(this).balance;
        uint256 wethBalanceBefore = IERC20(W_ETH_ADDRESS).balanceOf(
            address(this)
        );
        uint256 idealOut = ((ethPerDerivative(true) * _amount) / 1e18);
        IERC20(rethAddress()).approve(ROCKET_SWAP_ROUTER, _amount);

        // swaps from reth into weth using 100% balancer pool
        RocketSwapRouterInterface(ROCKET_SWAP_ROUTER).swapFrom(
            0,
            10,
            0,
            idealOut,
            _amount
        );
        uint256 wethBalanceAfter = IERC20(W_ETH_ADDRESS).balanceOf(
            address(this)
        );
        IWETH(W_ETH_ADDRESS).withdraw(wethBalanceAfter - wethBalanceBefore);
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
        @notice - Deposit into reth derivative
     */
    function deposit() external payable onlyOwner returns (uint256) {
        uint256 rethBalanceBefore = IERC20(rethAddress()).balanceOf(
            address(this)
        );
        balancerSwap(msg.value);
        uint256 received = IERC20(rethAddress()).balanceOf(address(this)) -
            rethBalanceBefore;
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
            return uint256(cl.answer);
        } else {
            revert("Chainlink Failed Reth");
        }
    }

    /**
        @notice - Total derivative balance
     */
    function balance() external view returns (uint256) {
        return underlyingBalance;
    }

    function balancerSwap(uint256 _amount) private {
        if (_amount == 0) {
            return;
        }
        IVault.SingleSwap memory swap;
        swap
            .poolId = 0x1e19cf2d73a72ef1332c882f20534b6519be0276000200000000000000000112;
        swap.kind = IVault.SwapKind.GIVEN_IN;
        swap.assetIn = address(W_ETH_ADDRESS);
        swap.assetOut = address(rethAddress());
        swap.amount = _amount;

        IVault.FundManagement memory fundManagement;
        fundManagement.sender = address(this);
        fundManagement.recipient = address(this);
        fundManagement.fromInternalBalance = false;
        fundManagement.toInternalBalance = false;

        IWETH(W_ETH_ADDRESS).deposit{value: _amount}();
        IERC20(W_ETH_ADDRESS).approve(address(BALANCER_VAULT), _amount);
        // Execute swap
        BALANCER_VAULT.swap(swap, fundManagement, 0, block.timestamp);
    }
}
