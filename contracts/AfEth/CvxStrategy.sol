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

contract CvxStrategy is Initializable, OwnableUpgradeable, CvxLockManager {
    event UpdateCrvPool(address indexed newCrvPool, address oldCrvPool);
    event SetEmissionsPerYear(uint256 indexed year, uint256 emissions);
    event Staked(uint256 indexed position, address indexed user);
    event Unstaked(uint256 indexed position, address indexed user);

    mapping(uint256 => uint256) public crvEmissionsPerYear;

    uint256 positionId;

    AggregatorV3Interface constant chainLinkCvxEthFeed =
        AggregatorV3Interface(0xC9CbF687f43176B302F03f5e58470b77D07c61c6);
    AggregatorV3Interface constant chainLinkCrvEthFeed =
        AggregatorV3Interface(0x8a12Be339B0cD1829b91Adc01977caa5E9ac121e);

    ISwapRouter constant swapRouter =
        ISwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    address constant veCRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    address constant wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address afEth;
    address crvPool;
    address safEth;

    struct Position {
        address owner; // owner of position
        uint256 curveBalance; // crv Pool LP amount
        uint256 afEthAmount; // afEth amount minted
        uint256 safEthAmount; // safEth amount minted
        uint256 createdAt; // block.timestamp
        bool claimed; // user has unstaked position
    }

    mapping(uint256 => Position) public positions;

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
    function initialize(address _safEth, address _afEth) external initializer {
        _transferOwnership(msg.sender);

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

        initializeLockManager();
    }

    function stake() public payable returns (uint256 id) {
        require(crvPool != address(0), "Pool not initialized");

        uint256 ratio = getAsymmetryRatio(150000000000000000); // TODO: make apr changeable
        uint256 ethAmountForCvx = (msg.value * ratio) / 1e18;
        uint256 ethAmountForSafEth = (msg.value - ethAmountForCvx);
        uint256 cvxAmount = swapCvx(ethAmountForCvx);
        id = positionId;

        lockCvx(cvxAmount, id, msg.sender);

        uint256 safEthAmount = ISafEth(safEth).stake{value: ethAmountForSafEth}(
            0 // TODO: set minAmount
        );
        uint256 mintAmount = safEthAmount;
        IAfEth(afEth).mint(address(this), mintAmount);
        uint256 crvLpAmount = addAfEthCrvLiquidity(
            crvPool,
            mintAmount,
            mintAmount
        );

        // storage of individual balances associated w/ user deposit
        positions[id] = Position({
            owner: msg.sender,
            curveBalance: crvLpAmount,
            afEthAmount: mintAmount,
            safEthAmount: safEthAmount,
            createdAt: block.timestamp,
            claimed: false
        });
        positionId++;
        emit Staked(id, msg.sender);
    }

    function unstake(bool _instantWithdraw, uint256 _id) external payable {
        uint256 id = _id;
        Position storage position = positions[id];
        require(position.claimed == false, "position claimed");
        require(position.owner == msg.sender, "not owner");
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
        uint256 afEthBalanceAfter = IERC20(afEth).balanceOf(address(this));
        uint256 safEthBalanceAfter = IERC20(safEth).balanceOf(address(this));
        uint256 afEthBalance = afEthBalanceAfter - afEthBalanceBefore;
        uint256 safEthBalance = safEthBalanceAfter - safEthBalanceBefore;
        IAfEth(afEth).burn(address(this), afEthBalance);
        ISafEth(safEth).unstake(safEthBalance, 0); // TODO: add minOut
        uint256 ethBalanceAfter = address(this).balance;

        // solhint-disable-next-line
        (bool sent, ) = address(msg.sender).call{
            value: ethBalanceAfter - ethBalanceBefore
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
        IERC20(tokenIn).approve(address(swapRouter), amountIn);
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
        amountOut = swapRouter.exactInputSingle(params);
    }

    function swapCvx(uint256 amount) private returns (uint256 amountOut) {
        IWETH(wETH).deposit{value: amount}();
        uint256 amountSwapped = swapExactInputSingleHop(
            wETH,
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
            uint256(100000), // TODO: why hardcoded
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
        this.stake{value: msg.value}();
    }

    receive() external payable {}
}
