// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../interfaces/uniswap/ISwapRouter.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/ISnapshotDelegationRegistry.sol";
import "../interfaces/convex/ILockedCvx.sol";
import "../interfaces/convex/IClaimZap.sol";
import "../interfaces/curve/ICvxCrvCrvPool.sol";
import "../interfaces/curve/IFxsEthPool.sol";
import "../interfaces/curve/ICrvEthPool.sol";
import "../interfaces/curve/ICvxFxsFxsPool.sol";
import "../interfaces/curve/IAfEthPool.sol";
import "../interfaces/ISafEth.sol";
import "../interfaces/IAfEth.sol";
import "./CvxLockManager.sol";
import "./CvxStrategyStorage.sol";
import "../interfaces/convex/IConvexRewardPool.sol";
import "../interfaces/convex/IConvexBooster.sol";

contract CvxStrategy is Initializable, OwnableUpgradeable, CvxLockManager {
    event UpdateCrvPool(address indexed newCrvPool, address oldCrvPool);
    event SetEmissionsPerYear(uint256 indexed year, uint256 emissions);
    event Staked(uint256 indexed position, address indexed user);
    event Unstaked(uint256 indexed position, address indexed user);

    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setEmissionsPerYear(
        uint256 year,
        uint256 emissions
    ) public onlyOwner {
        crvEmissionsPerYear[year] = emissions;
        emit SetEmissionsPerYear(year, emissions);
    }

    /**
        @notice - Function to initialize values for the contracts
        @dev - This replaces the constructor for upgradeable contracts
    */
    function initialize(
        address _safEth,
        address _afEth,
        address _rewardsExtraStream
    ) external initializer {
        _transferOwnership(msg.sender);
        chainLinkCvxEthFeed = AggregatorV3Interface(CHAINLINK_CVX);
        chainLinkCrvEthFeed = AggregatorV3Interface(CHAINLINK_CRV);
        safEth = _safEth;
        afEth = _afEth;

        // emissions of CRV per year
        crvEmissionsPerYear[1] = 274815283;
        crvEmissionsPerYear[2] = 231091186;
        crvEmissionsPerYear[3] = 194323750;
        crvEmissionsPerYear[4] = 163406144;
        crvEmissionsPerYear[5] = 137407641;
        crvEmissionsPerYear[6] = 115545593;
        crvEmissionsPerYear[7] = 97161875;
        crvEmissionsPerYear[8] = 81703072;
        crvEmissionsPerYear[9] = 68703820;
        crvEmissionsPerYear[10] = 57772796;

        initializeLockManager(_rewardsExtraStream);

        // I THINK this is the booster for all convex pools and wont change
        lpBoosterAddress = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

        // TODO set this to our pool lp token when mainnet launched
        lpTokenAddress = 0x0000000000000000000000000000000000000000;
        // TODO set this to the convex reward pool for our LP token when mainnet launched
        lpRewardPoolAddress = 0x0000000000000000000000000000000000000000;
    }

    function stake() public payable returns (uint256 id) {
        require(crvPool != address(0), "Pool not initialized");

        uint256 ratio = getAsymmetryRatio(150000000000000000); // TODO: make apr changeable
        uint256 ethAmountForCvx = (msg.value * ratio) / 1e18;
        uint256 ethAmountForSafEth = (msg.value - ethAmountForCvx);
        uint256 cvxAmount = swapCvx(ethAmountForCvx);
        id = positionId;

        lockCvx(cvxAmount, id, msg.sender);
        uint256 mintAmount = ISafEth(safEth).stake{value: ethAmountForSafEth}(
            0 // TODO: set minAmount
        );
        IAfEth(afEth).mint(address(this), mintAmount);
        uint256 crvLpAmount = addAfEthCrvLiquidity(
            crvPool,
            mintAmount,
            mintAmount
        );

        // TODO uncomment this line when stakeLpTokens() works with our mainnet contracts
        // stakeLpTokens();

        // storage of individual balances associated w/ user deposit
        positions[id] = Position({
            owner: msg.sender,
            curveBalance: crvLpAmount,
            afEthAmount: mintAmount,
            safEthAmount: mintAmount,
            createdAt: block.timestamp,
            claimed: false,
            ethAmountForSafEth: ethAmountForSafEth
        });
        positionId++;
        emit Staked(id, msg.sender);
    }

    /// stake lp tokens into convex
    function stakeLpTokens() private {
        // TODO set this to our pool id once launched
        uint256 poolId = 0;
        IERC20(crvPool).approve(address(lpBoosterAddress), type(uint256).max);
        IConvexBooster(lpBoosterAddress).depositAll(poolId, false);
    }

    function unstake(bool _instantWithdraw, uint256 _id) external payable {
        uint256 id = _id;
        Position storage position = positions[id];
        require(position.claimed == false, "position claimed");
        require(position.owner == msg.sender, "Not owner");
        position.claimed = true;
        if (_instantWithdraw) {
            // TODO: add instant withdraw function
            // fees: 119 days - 1% per day to max 12% fee: 88 days to min fee
            // 119 - 88 = 31
            // block.timestamp - positions[createdAt] = time locked
            // 1 day = 86400 seconds
            // burn NFT
            // swap CVX for ETH
            // transfer ETH to user minus fee for unlock
            // fee schedule:
        } else {
            requestUnlockCvx(id, msg.sender);
        }
        uint256 ethBalanceBefore = address(this).balance;
        uint256 afEthBalanceBefore = IERC20(afEth).balanceOf(address(this));
        uint256 safEthBalanceBefore = IERC20(safEth).balanceOf(address(this));

        withdrawCrvPool(crvPool, position.curveBalance);
        IAfEth(afEth).burn(
            address(this),
            IERC20(afEth).balanceOf(address(this)) - afEthBalanceBefore
        );
        ISafEth(safEth).unstake(
            IERC20(safEth).balanceOf(address(this)) - safEthBalanceBefore,
            0
        ); // TODO: add minOut ~.5% slippage

        uint256 ethUnstaked = address(this).balance - ethBalanceBefore;
        uint256 safEthRewards = position.ethAmountForSafEth < ethUnstaked
            ? ethUnstaked - position.ethAmountForSafEth
            : 0;
        harvestedEthRewards += safEthRewards;

        // solhint-disable-next-line
        (bool sent, ) = address(msg.sender).call{
            value: ethUnstaked - safEthRewards
        }("");
        require(sent, "Failed to send Ether");

        emit Unstaked(id, msg.sender);
    }

    function getAsymmetryRatio(
        uint256 apy
    ) public view returns (uint256 ratio) {
        uint256 crvEmissionsThisYear = crvEmissionsPerYear[
            ((block.timestamp - 1597471200) / 31556926) + 1
        ];
        uint256 cvxTotalSupplyAsCrv = (crvPerCvx() *
            IERC20(CVX).totalSupply()) / 1e18;
        uint256 supplyEmissionRatio = cvxTotalSupplyAsCrv /
            crvEmissionsThisYear;
        uint256 ratioPercentage = supplyEmissionRatio * apy;
        return (ratioPercentage) / (1e18 + (ratioPercentage / 1e18));
    }

    function crvPerCvx() public view returns (uint256) {
        (, int256 chainLinkCrvEthPrice, , , ) = chainLinkCrvEthFeed
            .latestRoundData();
        if (chainLinkCrvEthPrice < 0) chainLinkCrvEthPrice = 0;
        (, int256 chainLinkCvxEthPrice, , , ) = chainLinkCvxEthFeed
            .latestRoundData();
        if (chainLinkCrvEthPrice < 0) chainLinkCrvEthPrice = 0;
        return
            (uint256(chainLinkCvxEthPrice) * 1e18) /
            uint256(chainLinkCrvEthPrice);
    }

    function swapExactInputSingleHop(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint256 amountIn
    ) private returns (uint256 amountOut) {
        IERC20(tokenIn).approve(SWAP_ROUTER, amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: 1, // TODO: fix slippage
                sqrtPriceLimitX96: 0
            });
        amountOut = ISwapRouter(SWAP_ROUTER).exactInputSingle(params);
    }

    function swapCvx(uint256 amount) private returns (uint256 amountOut) {
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        IWETH(WETH).deposit{value: amount}();
        uint256 amountSwapped = swapExactInputSingleHop(
            WETH,
            CVX,
            10000,
            amount
        );
        return amountSwapped;
    }

    // strat has afEth, deposit in CRV pool
    function addAfEthCrvLiquidity(
        address _pool,
        uint256 _safEthAmount,
        uint256 _afEthAmount
    ) private returns (uint256 mintAmount) {
        require(
            _safEthAmount <= IERC20(safEth).balanceOf(address(this)),
            "Not Enough safETH"
        );
        require(
            _afEthAmount <= IERC20(afEth).balanceOf(address(this)),
            "Not Enough afETH"
        );

        IERC20(safEth).approve(_pool, _safEthAmount);
        IERC20(afEth).approve(_pool, _afEthAmount);

        uint256[2] memory _amounts = [_afEthAmount, _safEthAmount];
        uint256 poolTokensMinted = IAfEthPool(_pool).add_liquidity(
            _amounts,
            0, // TODO: add min mint amount
            false
        );
        return (poolTokensMinted);
    }

    function withdrawCrvPool(address _pool, uint256 _amount) private {
        uint256[2] memory min_amounts;
        // TODO: update min amounts
        min_amounts[0] = 0;
        min_amounts[1] = 0;
        IAfEthPool(_pool).remove_liquidity(_amount, min_amounts);
    }

    function updateCrvPool(address _crvPool) external payable onlyOwner {
        require(msg.value > 0, "Must seed pool");
        emit UpdateCrvPool(_crvPool, crvPool);
        crvPool = _crvPool;
        uint256 mintAmount = ISafEth(safEth).stake{value: msg.value}(0);
        IAfEth(afEth).mint(address(this), mintAmount);
        addAfEthCrvLiquidity(
            crvPool,
            IERC20(safEth).balanceOf(address(this)),
            IERC20(afEth).balanceOf(address(this))
        );
    }

    function withdrawHarvestedRewards() external onlyOwner {
        // solhint-disable-next-line
        (bool sent, ) = address(msg.sender).call{value: harvestedEthRewards}("");
        require(sent, "Failed to send Ether");
    }

    receive() external payable {}
}
