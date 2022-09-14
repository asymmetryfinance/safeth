// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "uniswap/interfaces/ISwapRouter.sol";
import {TransferHelper} from "uniswap/libraries/TransferHelper.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "./interfaces/convex/ILockedCvx.sol";
import "./interfaces/convex/ICvxLockerV2.sol";
import "./tokens/grCVX1155.sol";
import "./interfaces/curve/ICrvEthPool.sol";
import {ICurve} from "./interfaces/curve/ICurve.sol";

contract StrategyGoldenRatio is ERC1155Holder {
    // Contract Addresses
    address constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant CvxLockerV2 = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;
    // address for ETH/stETH crv pool
    address private constant stEthCrvPool =
        0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    // address for ETH/stETH crv LP token
    address private constant lpToken =
        0x06325440D014e39736583c165C2963BA99fAf14E;

    // Init
    IWETH private weth = IWETH(WETH9);
    IERC20 private cvx = IERC20(CVX);
    ICvxLockerV2 constant locker = ICvxLockerV2(CvxLockerV2);
    ILockedCvx constant lockedCvx = ILockedCvx(CvxLockerV2);
    grCVX1155 private cvxNft = new grCVX1155();

    ISwapRouter constant router =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function swapExactInputSingleHop(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint amountIn
    ) public returns (uint amountOut) {
        //TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        TransferHelper.safeApprove(tokenIn, address(router), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            });
        amountOut = router.exactInputSingle(params);
        console.log(
            "Balance of CVX in sender contract:",
            cvx.balanceOf(msg.sender)
        );
    }

    function swapCvx() public returns (uint amountOut) {
        weth.deposit{value: 1e18}();
        weth.approve(address(this), 1e18);
        uint amountSwapped = swapExactInputSingleHop(WETH9, CVX, 10000, 1e18);
        return amountSwapped;
    }

    function lockCvx(uint _amountOut) public returns (uint256 amount) {
        uint amountOut = _amountOut;
        cvx.approve(CvxLockerV2, amountOut);
        console.log(
            "Balance of CVX in sender contract prior to lock:",
            cvx.balanceOf(msg.sender)
        );
        console.log(
            "Balance of CVX in strat contract prior to lock:",
            cvx.balanceOf(address(this))
        );
        locker.lock(address(this), amountOut, 0);
        uint256 lockedCvxAmount = lockedCvx.lockedBalanceOf(address(this));
        return lockedCvxAmount;
    }

    function mintCvxNft(uint _amountOut) public returns (uint256 balance) {
        uint amountOut = _amountOut;
        cvxNft.mint(1, amountOut, address(this));
        uint256 minted1155 = cvxNft.balanceOf(address(this), 1);
        console.log("sender contract minted:", cvxNft.balanceOf(msg.sender, 1));
        return minted1155;
    }

    function depositCvx() public returns (uint256 balance) {}

    function depositBalTokens() public {}

    function mintBundleNft() public {}

    function mintGrEth() public {}

    function addCrvLiquidity() public {
        console.log("sender bal:", msg.sender.balance);
        console.log("this add bal:", address(this).balance);
        uint256[2] memory _amounts;
        _amounts = [uint256(1e18), 0];
        uint256 mintAmt = ICrvEthPool(stEthCrvPool).add_liquidity{
            value: _amounts[0]
        }(_amounts, 0);
        console.log("LP tokens minted:", mintAmt);
        uint256 lpMinted = IERC20(lpToken).balanceOf(address(this));
        console.log(lpMinted);
    }

    // put it all together
    function deposit() public {}

    receive() external payable {}
}
