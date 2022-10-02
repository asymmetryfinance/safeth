// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
// GR Interfaces
import "./interfaces/IController.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/convex/ILockedCvx.sol";
import "./interfaces/convex/ICvxLockerV2.sol";
import "./tokens/grCVX1155.sol";
import "./tokens/grBundle1155.sol";
import "./interfaces/IgrETH.sol";
import "./interfaces/Igr1155.sol";
// OZ
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
// Uniswap
import "uniswap/interfaces/ISwapRouter.sol";
import {TransferHelper} from "uniswap/libraries/TransferHelper.sol";
// Curve
import "./interfaces/curve/ICrvEthPool.sol";
import "./interfaces/curve/ICurvePool.sol";
// RocketPool
import "./interfaces/rocketpool/RocketDepositPoolInterface.sol";
import "./interfaces/rocketpool/RocketStorageInterface.sol";
import "./interfaces/rocketpool/RocketTokenRETHInterface.sol";
// Lido
import "./interfaces/lido/IWStETH.sol";
import "./interfaces/lido/IstETH.sol";
// Balancer
// balancer Vault interface: https://github.com/balancer-labs/balancer-v2-monorepo/blob/weighted-deployment/contracts/vault/interfaces/IVault.sol
import "./interfaces/balancer/IVault.sol";
import "./interfaces/balancer/IBalancerHelpers.sol";

contract StrategyGoldenRatio is ERC1155Holder {
    struct Position {
        uint256 positionID;
        address userAddress;
        uint256 rocketBalances; // rETH
        uint256 lidoBalances; // wstETH
        uint256 curveBalances; // crv Pool LP amount
        uint256 convexBalances; // CVX locked amount amount
        uint256 balancerBalances; // bal LP amount
        uint256 cvxNFTID;
        uint256 bundleNFTID;
        uint256 grETH; // amount grETH minted to user
        uint256 createdAt; // block.timestamp
    }

    // map user address to Position struct
    mapping(address => Position) public positions;
    uint256 currentPositionId;

    // Contract Addresses
    address constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant want = address(WETH9);
    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant CvxLockerV2 = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;
    address constant wStEthToken = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant stEthToken = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant lidoCrvPool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address constant balPoolEthAddress =
        0x0000000000000000000000000000000000000000;
    RocketStorageInterface rocketStorage = RocketStorageInterface(address(0));
    address constant deployCurvePool =
        0xB9fC157394Af804a3578134A6585C0dc9cc990d4;

    address public governance;
    address public controller;
    address public strategist;

    IWETH private weth = IWETH(WETH9);
    IERC20 private cvx = IERC20(CVX);
    IERC20 private reth = IERC20(RETH);
    ICvxLockerV2 constant locker = ICvxLockerV2(CvxLockerV2);
    ILockedCvx constant lockedCvx = ILockedCvx(CvxLockerV2);
    IWStETH private wstEth = IWStETH(payable(wStEthToken));
    ICrvEthPool private lidoPool = ICrvEthPool(lidoCrvPool);
    ICurvePool private curve = ICurvePool(deployCurvePool);

    ISwapRouter constant router =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address currentDepositor;
    address currentWithdrawer;

    address grETH;
    address pool;
    address CVXNFT;
    address bundleNFT;
    // cvx NFT ID starts at 0
    uint256 currentCvxNftId;
    // Bundle NFT ID starts at 100
    uint256 currentBundleNftId = 100;

    uint256 totalGrEthBalance;

    // balancer pool things
    address private wstEthBalPool = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    IVault balancer = IVault(wstEthBalPool);
    bytes32 balPoolId =
        0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080;
    address private balancerHelpers =
        0x5aDDCCa35b7A0D07C74063c48700C8590E87864E;
    IBalancerHelpers helper = IBalancerHelpers(balancerHelpers);

    constructor(
        address token,
        address _controller,
        address _rocketStorageAddress,
        address cvxNft,
        address bundleNft
    ) {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
        rocketStorage = RocketStorageInterface(_rocketStorageAddress);
        grETH = token;
        CVXNFT = cvxNft;
        bundleNFT = bundleNft;
    }

    /*//////////////////////////////////////////////////////////////
                        OPEN/CLOSE POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    function openPosition(address sender, uint256 assets) public payable {
        address pool = deployGrPool(grETH);
        currentDepositor = sender;
        weth.withdraw(assets);
        uint256 cvxAmountOut = swapCvx(assets - 32e18);
        uint256 amountCvxLocked = lockCvx(cvxAmountOut);
        (uint256 cvxNftBalance, uint256 _cvxNFTID) = mintCvxNft(
            sender,
            amountCvxLocked
        );
        uint256 wstEthMinted = depositWstEth(assets - 40e18);
        uint256 rEthMinted = depositREth(assets - 40e18);
        uint256 balLpAmount = depositBalTokens(wstEthMinted);
        uint256 bundleNftId = mintBundleNft(
            currentCvxNftId,
            amountCvxLocked,
            balLpAmount
        );
        mintGrEth(16e18);
        uint256 crvLpAmount = addGrEthCrvLiquidity(pool, 16e18);
        require(
            positions[currentDepositor].userAddress != currentDepositor,
            "User already has position."
        );
        uint256 newPositionID = ++currentPositionId;

        // storage of individual balances associated w/ user deposit
        positions[currentDepositor] = Position({
            positionID: newPositionID,
            userAddress: currentDepositor,
            rocketBalances: rEthMinted,
            lidoBalances: wstEthMinted,
            curveBalances: crvLpAmount,
            convexBalances: amountCvxLocked,
            balancerBalances: balLpAmount,
            cvxNFTID: _cvxNFTID,
            bundleNFTID: bundleNftId,
            grETH: 16e18,
            createdAt: block.timestamp
        });

        console.log("positions.id", positions[currentDepositor].positionID);
        console.log(
            "positions.userAddress",
            positions[currentDepositor].userAddress
        );
        console.log(
            "positions.rocketBalances",
            positions[currentDepositor].rocketBalances
        );
        console.log(
            "positions.lidoBalances",
            positions[currentDepositor].lidoBalances
        );
        console.log(
            "positions.curveBalances",
            positions[currentDepositor].curveBalances
        );
        console.log(
            "positions.convexBalances",
            positions[currentDepositor].convexBalances
        );
        console.log(
            "positions.balancerBalances",
            positions[currentDepositor].balancerBalances
        );
        console.log("positions.cvxNFTID", positions[currentDepositor].cvxNFTID);
        console.log(
            "positions.bundleNFTID",
            positions[currentDepositor].bundleNFTID
        );
        console.log("positions.grETH", positions[currentDepositor].grETH);
        console.log(
            "positions.createdAt",
            positions[currentDepositor].createdAt
        );
    }

    // add support for CVX burn or keep and transfer NFT to user
    // must transfer amount out tokens to vault
    function closePosition(address sender) public {
        currentWithdrawer = sender;
        withdrawCRVPool(pool, 32e18);
        burn(16e18);
        burnBundleNFT(sender);
        uint256 wstETH2Unwrap = withdrawBalTokens();
        withdrawREth();
        withdrawWstEth(wstETH2Unwrap);
        weth.withdraw(weth.balanceOf(address(this)));
        //uint256 lockedCvxAmount = lockedCvx.lockedBalanceOf(address(this));
        //console.log("CVX lp after withdraw:", lockedCvxAmount);
        address vault = IController(controller).getVault(WETH9);
        (bool sent, ) = address(vault).call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
        console.log("-----------");
        console.log("positions.id", positions[sender].positionID);
        console.log("positions.userAddress", positions[sender].userAddress);
        console.log(
            "positions.rocketBalances",
            positions[sender].rocketBalances
        );
        console.log("positions.lidoBalances", positions[sender].lidoBalances);
        console.log("positions.curveBalances", positions[sender].curveBalances);
        console.log(
            "positions.convexBalances",
            positions[sender].convexBalances
        );
        console.log(
            "positions.balancerBalances",
            positions[sender].balancerBalances
        );
        console.log("positions.cvxNFTID", positions[sender].cvxNFTID);
        console.log("positions.bundleNFTID", positions[sender].bundleNFTID);
        console.log("positions.grETH", positions[sender].grETH);
        console.log("positions.createdAt", positions[sender].createdAt);
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY METHODS
    //////////////////////////////////////////////////////////////*/

    function swapExactInputSingleHop(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint amountIn
    ) public returns (uint amountOut) {
        TransferHelper.safeApprove(tokenIn, address(router), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            });
        amountOut = router.exactInputSingle(params);
    }

    function swapCvx(uint256 amount) internal returns (uint256 amountOut) {
        weth.deposit{value: amount}();
        weth.approve(address(controller), amount);
        uint256 amountSwapped = swapExactInputSingleHop(
            WETH9,
            CVX,
            10000,
            amount
        );
        return amountSwapped;
    }

    function lockCvx(uint _amountOut) public returns (uint256 amount) {
        uint amountOut = _amountOut;
        cvx.approve(CvxLockerV2, amountOut);
        locker.lock(address(this), amountOut, 0);
        uint256 lockedCvxAmount = lockedCvx.lockedBalanceOf(address(this));
        return lockedCvxAmount;
    }

    // utilize Lido's wstETH shortcut by sending ETH to its fallback function
    // send ETH and bypass stETH, recieve wstETH for BAL pool
    function depositWstEth(uint256 amount)
        public
        payable
        returns (uint256 wstEthMintAmount)
    {
        require(amount == 8e18, "Invalid Deposit");
        uint256 wstEthBalance1 = wstEth.balanceOf(address(this));
        (bool sent, ) = address(wstEth).call{value: amount}("");
        require(sent, "Failed to send Ether");
        uint256 wstEthBalance2 = wstEth.balanceOf(address(this));
        uint256 wstEthAmount = wstEthBalance2 - wstEthBalance1;
        console.log("-----------");
        console.log("wstETH amount before bal pool:", wstEthAmount);
        console.log("-----------");
        return (wstEthAmount);
    }

    function depositREth(uint256 amount)
        public
        payable
        returns (uint256 rEthAmount)
    {
        require(amount == 8e18, "Invalid Deposit");
        // Per RocketPool Docs query deposit pool address each time it is used
        address rocketDepositPoolAddress = rocketStorage.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketDepositPool"))
        );
        RocketDepositPoolInterface rocketDepositPool = RocketDepositPoolInterface(
                rocketDepositPoolAddress
            );
        address rocketTokenRETHAddress = rocketStorage.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))
        );
        RocketTokenRETHInterface rocketTokenRETH = RocketTokenRETHInterface(
            rocketTokenRETHAddress
        );
        uint256 rethBalance1 = rocketTokenRETH.balanceOf(address(this));
        rocketDepositPool.deposit{value: amount}();
        uint256 rethBalance2 = rocketTokenRETH.balanceOf(address(this));
        require(rethBalance2 > rethBalance1, "No rETH was minted");
        uint256 rethMinted = rethBalance2 - rethBalance1;
        //rocketBalances[currentDepositor] += rethMinted;
        return (rethMinted);
    }

    function depositBalTokens(uint256 amount)
        public
        returns (uint256 lpAmount)
    {
        address[] memory _assets = new address[](2);
        uint256[] memory _amounts = new uint256[](2);
        _assets[0] = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        _assets[1] = 0x0000000000000000000000000000000000000000;
        _amounts[0] = amount;
        _amounts[1] = 0;
        uint256 joinKind = 1;
        bytes memory userDataEncoded = abi.encode(joinKind, _amounts);
        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest(
            _assets,
            _amounts,
            userDataEncoded,
            false
        );
        wstEth.approve(wstEthBalPool, amount);
        balancer.joinPool(balPoolId, address(this), address(this), request);
        return (
            ERC20(0x32296969Ef14EB0c6d29669C550D4a0449130230).balanceOf(
                address(this)
            )
        );
    }

    function withdrawREth() public {
        address rocketTokenRETHAddress = rocketStorage.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))
        );
        RocketTokenRETHInterface rocketTokenRETH = RocketTokenRETHInterface(
            rocketTokenRETHAddress
        );
        uint256 rethBalance1 = rocketTokenRETH.balanceOf(address(this));
        uint256 amount = positions[currentWithdrawer].rocketBalances;
        positions[currentWithdrawer].rocketBalances = 0;
        rocketTokenRETH.burn(amount);
        uint256 rethBalance2 = rocketTokenRETH.balanceOf(address(this));
        require(rethBalance1 > rethBalance2, "No rETH was burned");
        uint256 rethBurned = rethBalance1 - rethBalance2;
    }

    function withdrawWstEth(uint256 _amount) public {
        positions[currentWithdrawer].lidoBalances = 0;
        wstEth.unwrap(_amount);
        uint256 stEthBal = IERC20(stEthToken).balanceOf(address(this));
        IERC20(stEthToken).approve(lidoCrvPool, stEthBal);
        // convert stETH to ETH
        lidoPool.exchange(1, 0, stEthBal, 0);
    }

    // deploy new curve pool, add liquidity
    // strat has grETH, deposit in CRV pool
    function addGrEthCrvLiquidity(address pool, uint256 amount)
        public
        returns (uint256 mint)
    {
        address grETHPool = pool;
        uint256[2] memory _amounts;
        weth.deposit{value: amount}();
        weth.approve(grETHPool, amount);
        _amounts = [uint256(amount), amount];
        require(_amounts[0] == 16e18, "Invalid Deposit");
        IgrETH grEthToken = IgrETH(grETH);
        grEthToken.approve(grETHPool, amount);
        uint256 mintAmt = ICrvEthPool(grETHPool).add_liquidity(_amounts, 0);
        return (mintAmt);
    }

    function withdrawBalTokens() public returns (uint256 wstETH2Unwrap) {
        // bal lp amount
        uint256 amount = positions[currentWithdrawer].balancerBalances;
        address[] memory _assets = new address[](2);
        uint256[] memory _amounts = new uint256[](2);
        _assets[0] = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        _assets[1] = 0x0000000000000000000000000000000000000000;
        // account for slippage from Balancer withdrawal
        _amounts[0] = (positions[currentWithdrawer].lidoBalances * 99) / 100;
        _amounts[1] = 0;
        uint256 exitKind = 0;
        uint256 exitTokenIndex = 0;
        bytes memory userDataEncoded = abi.encode(
            exitKind,
            amount,
            exitTokenIndex
        );
        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest(
            _assets,
            _amounts,
            userDataEncoded,
            false
        );
        // (uint256 balIn, uint256[] memory amountsOut) = helper.queryExit(balPoolId,address(this),address(this),request);
        uint256 wBalance1 = wstEth.balanceOf(address(this));
        balancer.exitPool(balPoolId, address(this), address(this), request);
        uint256 wBalance2 = wstEth.balanceOf(address(this));
        require(wBalance2 > wBalance1, "No wstETH was withdrawn");
        uint256 wstETHWithdrawn = wBalance2 - wBalance1;
        return (wstETHWithdrawn);
    }

    function withdrawCRVPool(address pool, uint256 _amount) public {
        address grETHPool = pool;
        uint256[2] memory min_amounts;
        min_amounts[0] = 0;
        min_amounts[1] = 0;
        positions[currentWithdrawer].curveBalances = 0;
        uint256[2] memory returnAmt = ICrvEthPool(grETHPool).remove_liquidity(
            _amount,
            min_amounts
        );
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN METHODS
    //////////////////////////////////////////////////////////////*/

    function deployGrPool(address grEth) public returns (address) {
        string memory name = "Golden Ratio ETH";
        string memory symbol = "grETH";
        address[4] memory coins;
        coins = [
            grEth,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0x0000000000000000000000000000000000000000,
            0x0000000000000000000000000000000000000000
        ];
        uint256 _A = 1000;
        uint256 fee = 4000000;
        uint256 asset_type = 1;
        uint256 implementation_idx = 1;
        address deployedPool = curve.deploy_plain_pool(
            name,
            symbol,
            coins,
            _A,
            fee,
            asset_type,
            implementation_idx
        );
        pool = deployedPool;
        return (deployedPool);
    }

    function mintCvxNft(address sender, uint _amountLocked)
        public
        returns (uint256 balance, uint256 nftId)
    {
        uint amountLocked = _amountLocked;
        uint256 newCvxNftId = ++currentCvxNftId;
        IgrCVX1155(CVXNFT).mint(newCvxNftId, amountLocked, address(this));
        positions[sender].cvxNFTID = newCvxNftId;
        uint256 mintedCvx1155 = IgrCVX1155(CVXNFT).balanceOf(
            address(this),
            newCvxNftId
        );
        return (mintedCvx1155, newCvxNftId);
    }

    function mintBundleNft(
        uint256 cvxNftId,
        uint256 cvxAmount,
        uint256 balPoolTokens
    ) public returns (uint256 id) {
        uint256 newBundleNftId = ++currentBundleNftId;
        IgrBundle1155(bundleNFT).mint(
            cvxNftId,
            cvxAmount,
            newBundleNftId,
            balPoolTokens,
            address(this)
        );
        // positions[currentDepositor] = newBundleNftId;
        // bundleNFtBalances[newBundleNftId] = balPoolTokens;
        return (newBundleNftId);
    }

    function burnBundleNFT(address user) public {
        uint256[2] memory ids;
        uint256[2] memory amounts;
        ids[0] = positions[user].bundleNFTID;
        ids[1] = positions[user].cvxNFTID;
        amounts[0] = positions[user].balancerBalances;
        amounts[1] = positions[user].convexBalances;
        IgrBundle1155(bundleNFT).burnBatch(address(this), ids, amounts);
    }

    function mintGrEth(uint256 amount) public {
        IgrETH grEthToken = IgrETH(grETH);
        grEthToken.mint(address(this), amount);
    }

    // burn grETH
    function burn(uint256 amount) public {
        IgrETH grEthToken = IgrETH(grETH);
        positions[currentWithdrawer].grETH = 0;
        grEthToken.burn(address(this), amount);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    function getPool() public view returns (address) {
        return (pool);
    }

    function getName() external pure returns (string memory) {
        return "StrategyGoldenRatio";
    }

    /*//////////////////////////////////////////////////////////////
                            FALLBACK
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}
}
