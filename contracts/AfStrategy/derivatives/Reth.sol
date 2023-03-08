// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../interfaces/Iderivative.sol";
import "../../interfaces/frax/IsFrxEth.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/curve/ICrvEthPool.sol";
import "../../interfaces/frax/IFrxETHMinter.sol";
import "hardhat/console.sol";
import "../../interfaces/rocketpool/RocketStorageInterface.sol";
import "../../interfaces/rocketpool/RocketTokenRETHInterface.sol";
import "../../interfaces/rocketpool/RocketDepositPoolInterface.sol";
import "../../interfaces/IWETH.sol";
import "../../interfaces/uniswap/ISwapRouter.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../../interfaces/uniswap/IUniswapV3Pool.sol";
import "../../interfaces/uniswap/IUniswapV3Factory.sol";

contract Reth is IDERIVATIVE, Initializable, OwnableUpgradeable {
    address public constant rocketStorageAddress =
        0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46;
    uint256 public constant ROCKET_POOL_LIMIT = 5000000000000000000000;
    address public constant wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant uniswapRouter =
        0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address public constant uniV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    uint256 public maxSlippage;

    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // This replaces the constructor for upgradeable contracts
    function initialize() public initializer {
        _transferOwnership(msg.sender);
        maxSlippage = (5 * 10 ** 16); // 5%
    }

    function setMaxSlippage(uint slippage) public onlyOwner {
        maxSlippage = slippage;
    }

    function rethAddress() private view returns (address) {
        return
            RocketStorageInterface(rocketStorageAddress).getAddress(
                keccak256(
                    abi.encodePacked("contract.address", "rocketTokenRETH")
                )
            );
    }

    function swapExactInputSingleHop(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint256 amountIn,
        uint256 minOut
    ) private returns (uint256 amountOut) {
        IERC20(tokenIn).approve(uniswapRouter, amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: minOut,
                sqrtPriceLimitX96: 0
            });
        amountOut = ISwapRouter(uniswapRouter).exactInputSingle(params);
    }

    function withdraw(uint256 amount) public onlyOwner {
        RocketTokenRETHInterface(rethAddress()).burn(amount);
        (bool sent, ) = address(msg.sender).call{value: address(this).balance}(
            ""
        );
        require(sent, "Failed to send Ether");
    }

    function poolCanDeposit(uint256 amount) public view onlyOwner returns (bool) {
                address rocketDepositPoolAddress = RocketStorageInterface(
            rocketStorageAddress
        ).getAddress(
                keccak256(
                    abi.encodePacked("contract.address", "rocketDepositPool")
                )
            );
                RocketDepositPoolInterface rocketDepositPool = RocketDepositPoolInterface(
                rocketDepositPoolAddress
            );
        return (rocketDepositPool.getBalance() + amount <=
            ROCKET_POOL_LIMIT);
    }

    function deposit() public payable onlyOwner returns (uint256) {
        // Per RocketPool Docs query deposit pool address each time it is used
        address rocketDepositPoolAddress = RocketStorageInterface(
            rocketStorageAddress
        ).getAddress(
                keccak256(
                    abi.encodePacked("contract.address", "rocketDepositPool")
                )
            );
        RocketDepositPoolInterface rocketDepositPool = RocketDepositPoolInterface(
                rocketDepositPoolAddress
            );

        if (!poolCanDeposit(msg.value)) {
            uint256 minOut = (derivativePerEth(msg.value) *
                (10 ** 18 - maxSlippage)) / 10 ** 18;
            IWETH(wETH).deposit{value: msg.value}();
            uint256 amountSwapped = swapExactInputSingleHop(
                wETH,
                rethAddress(),
                500,
                msg.value,
                minOut
            );
            return amountSwapped;
        } else {
            address rocketTokenRETHAddress = RocketStorageInterface(
                rocketStorageAddress
            ).getAddress(
                    keccak256(
                        abi.encodePacked("contract.address", "rocketTokenRETH")
                    )
                );
            RocketTokenRETHInterface rocketTokenRETH = RocketTokenRETHInterface(
                rocketTokenRETHAddress
            );
            uint256 rethBalance1 = rocketTokenRETH.balanceOf(address(this));
            rocketDepositPool.deposit{value: msg.value}();
            uint256 rethBalance2 = rocketTokenRETH.balanceOf(address(this));
            require(rethBalance2 > rethBalance1, "No rETH was minted");
            uint256 rethMinted = rethBalance2 - rethBalance1;
            return (rethMinted);
        }
    }

    // eth price for acquiring the derivative (via native protocol or defi exchange)
    function ethPerDerivative(uint256 amount) public view returns (uint256) {
        if(poolCanDeposit(amount)) return RocketTokenRETHInterface(rethAddress()).getEthValue(amount);
        else return (poolPrice() * amount / (10 ** 18));
    }

    // inverse of ethPerDerivative
    function derivativePerEth(uint256 amount) public view returns (uint256) {
        if(poolCanDeposit(amount)) return RocketTokenRETHInterface(rethAddress()).getRethValue(amount);
        else {
            return (amount * 10 ** 18) / poolPrice();
        }
    }

    function totalEthValue() public view returns (uint256) {
        return ethPerDerivative(balance());
    }

    function balance() public view returns (uint256) {
        return IERC20(rethAddress()).balanceOf(address(this));
    }

    receive() external payable {}

    function poolPrice() public view returns (uint256) {

            address rocketTokenRETHAddress = RocketStorageInterface(
                rocketStorageAddress
            ).getAddress(
                    keccak256(
                        abi.encodePacked("contract.address", "rocketTokenRETH")
                    )
                );

        IUniswapV3Factory factory = IUniswapV3Factory(uniV3Factory);
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(rocketTokenRETHAddress, wETH, 500));
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        return (sqrtPriceX96 * (uint(sqrtPriceX96)) * (1e18)) >> (96 * 2);
    }
}
