// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "hardhat/console.sol";
// AF Interfaces
import "./interfaces/IWETH.sol";
import "./interfaces/convex/ILockedCvx.sol";
import "./interfaces/convex/ICvxLockerV2.sol";
import "./tokens/afCVX1155.sol";
import "./tokens/afBundle1155.sol";
import "./interfaces/IAfETH.sol";
import "./interfaces/IAf1155.sol";
// OZ
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
// Uniswap
import "./interfaces/uniswap/ISwapRouter.sol";
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

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract AsymmetryStrategy is ERC1155Holder {
    using Strings for uint256;

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
        uint256 afETH; // amount afETH minted to user
        uint256 createdAt; // block.timestamp
    }

    // curve emissions based on year
    mapping(uint256 => uint256) private emissionsPerYear;

    // map user address to Position struct
    mapping(address => Position) public positions;
    uint256 currentPositionId;

    // Contract Addresses
    address constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant rETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant veCRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    address constant CvxRewards = 0xCF50b810E57Ac33B91dCF525C6ddd9881B139332;
    address constant vlCvx = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;
    address constant cvxCrv = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;
    address constant wStEthToken = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant stEthToken = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant lidoCrvPool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address constant deployCurvePool =
        0xB9fC157394Af804a3578134A6585C0dc9cc990d4;

    AggregatorV3Interface constant chainLinkEthFeed =
        AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); // TODO: what if this is updated?
    AggregatorV3Interface constant chainLinkCvxFeed =
        AggregatorV3Interface(0xd962fC30A72A84cE50161031391756Bf2876Af5D);
    AggregatorV3Interface constant chainLinkCrvFeed =
        AggregatorV3Interface(0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f);

    RocketStorageInterface rocketStorage = RocketStorageInterface(address(0));

    address public governance;
    address public strategist;

    IWETH private weth = IWETH(WETH9);
    ICvxLockerV2 constant locker = ICvxLockerV2(vlCvx);
    ILockedCvx constant lockedCvx = ILockedCvx(vlCvx);
    IWStETH private wstEth = IWStETH(payable(wStEthToken));
    ICrvEthPool private lidoPool = ICrvEthPool(lidoCrvPool);
    ICurvePool private curve = ICurvePool(deployCurvePool);

    ISwapRouter constant router =
        ISwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    address currentDepositor;
    address currentWithdrawer;

    address afETH;
    address pool;
    address CVXNFT;
    address bundleNFT;
    // cvx NFT ID starts at 0
    uint256 currentCvxNftId;
    // Bundle NFT ID starts at 100
    uint256 currentBundleNftId = 100; // TODO: why?

    uint256 totalAfEthBalance;

    // balancer pool things
    address private wstEthBalPool = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    IVault balancer = IVault(wstEthBalPool);
    bytes32 balPoolId =
        0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080;
    address private balancerHelpers =
        0x5aDDCCa35b7A0D07C74063c48700C8590E87864E;
    IBalancerHelpers helper = IBalancerHelpers(balancerHelpers);

    uint256 constant ROCKET_POOL_LIMIT = 5000000000000000000000; // TODO: make changeable by owner

    constructor(
        address token,
        address _rocketStorageAddress,
        address cvxNft,
        address bundleNft
    ) {
        governance = msg.sender;
        strategist = msg.sender;
        rocketStorage = RocketStorageInterface(_rocketStorageAddress);
        afETH = token;
        CVXNFT = cvxNft;
        bundleNFT = bundleNft;
        // emissions of CRV per year
        emissionsPerYear[1] = 274815283;
        emissionsPerYear[2] = 231091186;
        emissionsPerYear[3] = 194323750;
        emissionsPerYear[4] = 163406144;
        emissionsPerYear[5] = 137407641;
        emissionsPerYear[6] = 115545593;
        emissionsPerYear[7] = 97161875;
        emissionsPerYear[8] = 81703072;
        emissionsPerYear[9] = 68703820;
        emissionsPerYear[10] = 57772796;
    }

    /*//////////////////////////////////////////////////////////////
                        OPEN/CLOSE POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    function openPosition() public payable {
        getAsymmetryRatio();
        address pool = deployAfPool(afETH); // TODO: why deploy curve pool everytime someone opens position?
        currentDepositor = msg.sender;
        uint256 openAmount = msg.value;
        uint256 ratio = getAsymmetryRatio();
        uint256 cvxAmount = (openAmount / 100) * ratio;
        uint256 ethAmount = (openAmount - cvxAmount) / 2; // will split half of remaining eth into derivatives
        uint256 numberOfDerivatives = 2;
        uint256 cvxAmountReceived = swapCvx(cvxAmount);
        uint256 amountCvxLocked = lockCvx(cvxAmountReceived);
        (uint256 cvxNftBalance, uint256 _cvxNFTID) = mintCvxNft(
            msg.sender,
            amountCvxLocked
        );
        uint256 wstEthMinted = depositWstEth(ethAmount / numberOfDerivatives);
        uint256 rEthMinted = depositREth(ethAmount / numberOfDerivatives);

        // TODO: create 4626 tokens for each derivative
        uint256 balLpAmount = depositBalTokens(wstEthMinted);
        uint256 bundleNftId = mintBundleNft(
            currentCvxNftId,
            amountCvxLocked,
            balLpAmount
        );
        mintAfEth(ethAmount);
        uint256 crvLpAmount = addAfEthCrvLiquidity(pool, ethAmount);
        require(
            positions[currentDepositor].userAddress != currentDepositor,
            "User already has position."
        );
        uint256 newPositionID = ++currentPositionId;

        // storage of individual balances associated w/ user deposit
        // TODO: This calculation doesn't update when afETH is transferred between wallets
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
            afETH: ethAmount,
            createdAt: block.timestamp
        });
    }

    // add support for CVX burn or keep and transfer NFT to user
    // must transfer amount out tokens to vault
    function closePosition(bool _instantWithdraw) public {
        currentWithdrawer = msg.sender;
        uint256 afEthBalance = IERC20(afETH).balanceOf(msg.sender);
        withdrawCVXNft(_instantWithdraw);
        withdrawCRVPool(pool, 32e18);
        burn(afEthBalance);
        burnBundleNFT(msg.sender);
        uint256 wstETH2Unwrap = withdrawBalTokens();
        withdrawREth();
        withdrawWstEth(wstETH2Unwrap);
        weth.withdraw(weth.balanceOf(address(this)));

        // address vault = IController(controller).getVault(WETH9);
        // (bool sent, ) = address(vault).call{value: address(this).balance}("");
        // require(sent, "Failed to send Ether");
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY METHODS
    //////////////////////////////////////////////////////////////*/

    function division(
        uint256 decimalPlaces,
        uint256 numerator,
        uint256 denominator
    )
        public
        view
        returns (
            uint256 quotient,
            uint256 remainder,
            string memory result
        )
    {
        uint256 factor = 10**decimalPlaces;
        quotient = numerator / denominator;
        bool rounding = 2 * ((numerator * factor) % denominator) >= denominator;
        remainder = ((numerator * factor) / denominator) % factor;
        if (rounding) {
            remainder += 1;
        }
        result = string(
            abi.encodePacked(
                quotient.toString(),
                ".",
                numToFixedLengthStr(decimalPlaces, remainder)
            )
        );
    }

    function numToFixedLengthStr(uint256 decimalPlaces, uint256 num)
        internal
        pure
        returns (string memory result)
    {
        bytes memory byteString;
        for (uint256 i = 0; i < decimalPlaces; i++) {
            uint256 remainder = num % 10;
            byteString = abi.encodePacked(remainder.toString(), byteString);
            num = num / 10;
        }
        result = string(byteString);
    }

    function getAsymmetryRatio() public returns (uint256 ratio) {
        int256 crvPrice = getCrvPriceData();
        int256 cvxPrice = getCvxPriceData();
        uint256 vcrvSupply = IERC20(veCRV).totalSupply();
        uint256 lockedCvxSupply = IERC20(CvxRewards).totalSupply();
        uint256 cvxSupply = IERC20(CVX).totalSupply();
        uint256 cvxCrvSupply = IERC20(cvxCrv).totalSupply();
        uint256 tvl = 10000000; // TODO: Should be ETH/afETH pool tvl
        uint256 apy = 1500;
        uint256 offset = 30;
        // uint256 vecrv_per_cvx = cvxCrvSupply / lockedCvxSupply;

        // 1597471200 - represents Aug 15th 2020 when curve was initialized
        // 31556926 - represents 1 year including leap years
        uint256 emissionYear = ((block.timestamp - 1597471200) / 31556926) + 1; // which year the emission schedule is on
        uint256 crvPerDay = emissionsPerYear[emissionYear] / 365;
        console.log("emissionYear", emissionYear);
        console.log("crvPerDay", crvPerDay);
        console.log("cvxSupply", (cvxSupply));

        // uint256 yearly_minted_crv_per_cvx = daily_minted_crv_per_cvx * 365;
        // console.log("yearly_minted_crv_per_cvx", yearly_minted_crv_per_cvx);

        // (uint256 quotient, uint256 remainder, string memory result) = division(
        //     30,
        //     crvPerDay,
        //     cvxSupply
        // );

        uint256 yearly_minted_crv_per_cvx = ((crvPerDay * 10**offset) / cvxSupply) *
            365 *
            uint(crvPrice);
        console.log(
            "yearly_minted_crv_per_cvx no price",
            ((crvPerDay * 10**offset) / cvxSupply) * 365
        );
        console.log("yearly_minted_crv_per_cvx", yearly_minted_crv_per_cvx);
        console.log(
            "((((apy + 10000) * tvl) - tvl))",
            ((((apy + 10000) * (tvl / 10000)) - tvl) * 10**offset)
        );
        uint256 cvx_amount = ((((apy + 10000) * (tvl / 10000)) - tvl) * 10**offset) / yearly_minted_crv_per_cvx;

        console.log("crv price", uint(crvPrice));
        console.log("cvx price", uint(cvxPrice));
        console.log("vcrvSupply supply", vcrvSupply);
        console.log("lockedCvxSupply supply", lockedCvxSupply);

        console.log("cvx amount", cvx_amount);
        uint256 allocationPercentage = (cvx_amount * uint(cvxPrice)) / (tvl * uint(cvxPrice));
        console.log("allocationPercentage", allocationPercentage);

        return 40;
    }

    function swapExactInputSingleHop(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint256 amountIn
    ) public returns (uint256 amountOut) {
        IERC20(tokenIn).approve(address(router), amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            });
        amountOut = router.exactInputSingle(params);
    }

    function swapCvx(uint256 amount) internal returns (uint256 amountOut) {
        weth.deposit{value: amount}();
        uint256 amountSwapped = swapExactInputSingleHop(
            WETH9,
            CVX,
            10000,
            amount
        );
        return amountSwapped;
    }

    function lockCvx(uint256 _amountOut) public returns (uint256 amount) {
        uint256 amountOut = _amountOut;
        IERC20(CVX).approve(vlCvx, amountOut);
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
        uint256 wstEthBalance1 = wstEth.balanceOf(address(this));
        (bool sent, ) = address(wstEth).call{value: amount}("");
        require(sent, "Failed to send Ether");
        uint256 wstEthBalance2 = wstEth.balanceOf(address(this));
        uint256 wstEthAmount = wstEthBalance2 - wstEthBalance1;
        return (wstEthAmount);
    }

    function depositREth(uint256 amount)
        public
        payable
        returns (uint256 rEthAmount)
    {
        // Per RocketPool Docs query deposit pool address each time it is used
        address rocketDepositPoolAddress = rocketStorage.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketDepositPool"))
        );
        RocketDepositPoolInterface rocketDepositPool = RocketDepositPoolInterface(
                rocketDepositPoolAddress
            );
        bool canDeposit = rocketDepositPool.getBalance() + amount <=
            ROCKET_POOL_LIMIT;
        if (!canDeposit) {
            weth.deposit{value: amount}();
            uint256 amountSwapped = swapExactInputSingleHop(
                WETH9,
                rETH,
                500,
                amount
            );
            return amountSwapped;
        } else {
            address rocketTokenRETHAddress = rocketStorage.getAddress(
                keccak256(
                    abi.encodePacked("contract.address", "rocketTokenRETH")
                )
            );
            RocketTokenRETHInterface rocketTokenRETH = RocketTokenRETHInterface(
                rocketTokenRETHAddress
            );
            uint256 rethBalance1 = rocketTokenRETH.balanceOf(address(this));
            uint256 ethBalance = address(this).balance;
            rocketDepositPool.deposit{value: amount}();
            uint256 rethBalance2 = rocketTokenRETH.balanceOf(address(this));
            require(rethBalance2 > rethBalance1, "No rETH was minted");
            uint256 rethMinted = rethBalance2 - rethBalance1;
            //rocketBalances[currentDepositor] += rethMinted;
            return (rethMinted);
        }
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
        console.log("Eth before swapping steth to eth:", address(this).balance);
        lidoPool.exchange(1, 0, stEthBal, 0);
        console.log("Eth after swapping steth to eth:", address(this).balance);
    }

    // deploy new curve pool, add liquidity
    // strat has afETH, deposit in CRV pool
    function addAfEthCrvLiquidity(address pool, uint256 amount)
        public
        returns (uint256 mint)
    {
        address afETHPool = pool;
        uint256[2] memory _amounts;
        weth.deposit{value: amount}();
        weth.approve(afETHPool, amount);
        _amounts = [uint256(amount), amount];
        IAfETH afEthToken = IAfETH(afETH);
        afEthToken.approve(afETHPool, amount);
        uint256 mintAmt = ICrvEthPool(afETHPool).add_liquidity(_amounts, 0);
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
        positions[currentWithdrawer].balancerBalances = 0;
        balancer.exitPool(balPoolId, address(this), address(this), request);
        uint256 wBalance2 = wstEth.balanceOf(address(this));
        require(wBalance2 > wBalance1, "No wstETH was withdrawn");
        uint256 wstETHWithdrawn = wBalance2 - wBalance1;
        return (wstETHWithdrawn);
    }

    function withdrawCRVPool(address pool, uint256 _amount) public {
        address afETHPool = pool;
        uint256[2] memory min_amounts;
        min_amounts[0] = 0;
        min_amounts[1] = 0;
        positions[currentWithdrawer].curveBalances = 0;
        uint256[2] memory returnAmt = ICrvEthPool(afETHPool).remove_liquidity(
            _amount,
            min_amounts
        );
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN METHODS
    //////////////////////////////////////////////////////////////*/

    function getCvxPriceData() public view returns (int256) {
        (, int price, , , ) = chainLinkCvxFeed.latestRoundData();
        uint8 decimals = chainLinkCvxFeed.decimals();
        console.log("dec", decimals);

        return price * 10**10;
    }

    function getCrvPriceData() public view returns (int256) {
        (, int price, , , ) = chainLinkCrvFeed.latestRoundData();
        uint8 decimals = chainLinkCrvFeed.decimals();
        console.log("dec crv", decimals);

        return price * 10**10;
    }

    // TODO: this shouldn't live here, should be a part of deploy scripts
    function deployAfPool(address afEth) public returns (address) {
        string memory name = "Asymmetry Finance ETH";
        string memory symbol = "afETH";
        address[4] memory coins;
        coins = [
            afEth,
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

    function mintCvxNft(address sender, uint256 _amountLocked)
        private
        returns (uint256 balance, uint256 nftId)
    {
        uint256 amountLocked = _amountLocked;
        uint256 newCvxNftId = ++currentCvxNftId;
        IAfCVX1155(CVXNFT).mint(newCvxNftId, amountLocked, address(this));
        positions[sender].cvxNFTID = newCvxNftId;
        uint256 mintedCvx1155 = IAfCVX1155(CVXNFT).balanceOf(
            address(this),
            newCvxNftId
        );
        return (mintedCvx1155, newCvxNftId);
    }

    function mintBundleNft(
        uint256 cvxNftId,
        uint256 cvxAmount,
        uint256 balPoolTokens
    ) private returns (uint256 id) {
        uint256 newBundleNftId = ++currentBundleNftId;
        IAfBundle1155(bundleNFT).mint(
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

    // user selection in front-end:
    // True - user is transferred the 1155 NFT holding their CVX deposit
    // until CVX lockup period is over (16 weeks plus days to thursday 0000 UTC)
    // False - user pays fee to unlock their CVX and burn their NFT
    function withdrawCVXNft(bool _instantWithdraw) private {
        if (_instantWithdraw == true) {
            // TODO: start withdraw vlCVX
            IAfCVX1155(CVXNFT).safeTransferFrom(
                address(this),
                currentWithdrawer,
                positions[currentWithdrawer].cvxNFTID,
                positions[currentWithdrawer].convexBalances,
                ""
            );
            console.log(
                "user balance of CVX NFT:",
                IAfCVX1155(CVXNFT).balanceOf(
                    currentWithdrawer,
                    positions[currentWithdrawer].cvxNFTID
                )
            );
        } else {
            console.log("instant withdraw: ", _instantWithdraw);
            // fees: 119 days - 1% per day to max 12% fee: 88 days to min fee
            // 119 - 88 = 31
            // block.timestamp - positions[createdAt] = time locked
            // 1 day = 86400 seconds
            // burn NFT
            // swap CVX for ETH
            // transfer ETH to user minus fee for unlock
            // fee schedule:
            //
        }
    }

    function burnBundleNFT(address user) private {
        uint256[2] memory ids;
        uint256[2] memory amounts;
        ids[0] = positions[user].bundleNFTID;
        ids[1] = positions[user].cvxNFTID;
        amounts[0] = positions[user].balancerBalances;
        amounts[1] = positions[user].convexBalances;
        IAfBundle1155(bundleNFT).burnBatch(address(this), ids, amounts);
    }

    function mintAfEth(uint256 amount) private {
        IAfETH afEthToken = IAfETH(afETH);
        afEthToken.mint(address(this), amount);
    }

    // burn afETH
    function burn(uint256 amount) private {
        IAfETH afEthToken = IAfETH(afETH);
        positions[currentWithdrawer].afETH = 0;
        afEthToken.burn(address(this), amount);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    function getPool() public view returns (address) {
        return (pool);
    }

    function getName() external pure returns (string memory) {
        return "StrategyAsymmetryFinance";
    }

    /*//////////////////////////////////////////////////////////////
                            FALLBACK
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}
}
