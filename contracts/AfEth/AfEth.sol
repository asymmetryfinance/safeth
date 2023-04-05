// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "../interfaces/uniswap/ISwapRouter.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/ISnapshotDelegationRegistry.sol";
import "./interfaces/convex/ILockedCvx.sol";
import "./interfaces/convex/IClaimZap.sol";
import "../interfaces/curve/ICvxCrvCrvPool.sol";
import "../interfaces/curve/IFxsEthPool.sol";
import "../interfaces/curve/ICrvEthPool.sol";
import "../interfaces/curve/ICvxFxsFxsPool.sol";
import "../interfaces/curve/IAfEthPool.sol";
import "./interfaces/IAf1155.sol";
import "./interfaces/ISafEth.sol";
import "hardhat/console.sol";
import "./CvxLockManager.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract AfEth is
    Initializable,
    ERC20Upgradeable,
    ERC1155Holder,
    OwnableUpgradeable,
    CvxLockManager
{
    event UpdateCrvPool(address indexed newCrvPool, address oldCrvPool);

    event SetEmissionsPerYear(uint256 indexed year, uint256 emissions);

    struct Position {
        uint256 positionID;
        uint256 curveBalances; // crv Pool LP amount
        uint256 convexBalances; // CVX locked amount amount
        uint256 cvxNFTID;
        uint256 bundleNFTID;
        uint256 afETH; // amount safETH minted to user
        uint256 createdAt; // block.timestamp
    }

    mapping(uint256 => uint256) public crvEmissionsPerYear;
    // map user address to Position struct
    mapping(address => Position) public positions;

    ISwapRouter constant swapRouter =
        ISwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    address constant veCRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;

    address constant wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 currentPositionId;

    address public constant SNAPSHOT_DELEGATE_REGISTRY =
        0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446;

    AggregatorV3Interface constant chainLinkCvxEthFeed =
        AggregatorV3Interface(0xC9CbF687f43176B302F03f5e58470b77D07c61c6);
    AggregatorV3Interface constant chainLinkCrvEthFeed =
        AggregatorV3Interface(0x8a12Be339B0cD1829b91Adc01977caa5E9ac121e);

    uint256 currentCvxNftId;
    uint256 currentBundleNftId;
    address afETH;
    address CVXNFT;
    address bundleNFT;
    address crvPool;
    address safEth;

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
        @param _tokenName - name of erc20
        @param _tokenSymbol - symbol of erc20
    */
    function initialize(
        address _cvxNft,
        address _bundleNft,
        address _safEth,
        string memory _tokenName,
        string memory _tokenSymbol
    ) external initializer {
        ERC20Upgradeable.__ERC20_init(_tokenName, _tokenSymbol);
        _transferOwnership(msg.sender);

        CVXNFT = _cvxNft;
        bundleNFT = _bundleNft;
        safEth = _safEth;

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

        // Assumes AfEth contract owns the vote locked convex
        // This will need to be done elseware if other contracts own or wrap the vote locked convex
        bytes32 vlCvxVoteDelegationId = 0x6376782e65746800000000000000000000000000000000000000000000000000;
        ISnapshotDelegationRegistry(SNAPSHOT_DELEGATE_REGISTRY).setDelegate(
            vlCvxVoteDelegationId,
            owner()
        );

        lastRelockEpoch = ILockedCvx(vlCVX).findEpochId(block.timestamp);
    }

    function stake() external payable {
        uint256 ratio = getAsymmetryRatio(150000000000000000); // TODO: make apr changeable
        uint256 cvxAmount = (msg.value * ratio) / 10 ** 18;
        uint256 ethAmount = (msg.value - cvxAmount) / 2;

        uint256 cvxAmountReceived = swapCvx(cvxAmount);
        (uint256 cvxNftBalance, uint256 _cvxNFTID) = mintCvxNft(
            msg.sender,
            cvxAmountReceived
        );

        lockCvx(cvxAmountReceived, _cvxNFTID, msg.sender);

        // TODO: return mint amount from stake function
        ISafEth(safEth).stake{value: ethAmount}();
        uint256 afEthAmount = ethAmount;

        _mint(address(this), afEthAmount);
        uint256 crvLpAmount = addAfEthCrvLiquidity(
            crvPool,
            ethAmount,
            afEthAmount
        );

        // storage of individual balances associated w/ user deposit
        // This calculation doesn't update when afETH is transferred between wallets
        // if we can not need this that'd be great, Maybe the bundle nft can handle the acounting from this
        uint256 newPositionID = ++currentPositionId;
        positions[msg.sender] = Position({
            positionID: newPositionID,
            curveBalances: crvLpAmount,
            convexBalances: cvxNftBalance,
            cvxNFTID: _cvxNFTID,
            bundleNFTID: 0, // maybe not needed yet,
            afETH: afEthAmount,
            createdAt: block.timestamp
        });
    }

    function unstake(uint256 positionId) public {
        requestUnlockCvx(positionId, msg.sender);
    }

    function getAsymmetryRatio(
        uint256 apy
    ) public view returns (uint256 ratio) {
        uint256 crvEmissionsThisYear = crvEmissionsPerYear[
            ((block.timestamp - 1597471200) / 31556926) + 1
        ];
        uint256 cvxTotalSupplyAsCrv = (crvPerCvx() *
            IERC20(CVX).totalSupply()) / 10 ** 18;
        uint256 supplyEmissionRatio = cvxTotalSupplyAsCrv /
            crvEmissionsThisYear;
        uint256 ratioPercentage = supplyEmissionRatio * apy;
        return (ratioPercentage) / (10 ** 18 + (ratioPercentage / 10 ** 18));
    }

    function crvPerCvx() private view returns (uint256) {
        (, int256 chainLinkCrvEthPrice, , , ) = chainLinkCrvEthFeed
            .latestRoundData();
        if (chainLinkCrvEthPrice < 0) chainLinkCrvEthPrice = 0;
        (, int256 chainLinkCvxEthPrice, , , ) = chainLinkCvxEthFeed
            .latestRoundData();
        if (chainLinkCrvEthPrice < 0) chainLinkCrvEthPrice = 0;
        return
            (uint256(chainLinkCvxEthPrice) * 10 ** 18) /
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
                amountOutMinimum: 1,
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

    // strat has afETH, deposit in CRV pool
    function addAfEthCrvLiquidity(
        address _pool,
        uint256 _ethAmount,
        uint256 _afEthAmount
    ) private returns (uint256 mintAmount) {
        require(_ethAmount <= address(this).balance, "Not Enough ETH");

        IWETH(wETH).deposit{value: _ethAmount}();
        IWETH(wETH).approve(_pool, _ethAmount);
        _approve(address(this), _pool, _afEthAmount);

        uint256[2] memory _amounts = [_afEthAmount, _ethAmount];
        uint256 poolTokensMinted = IAfEthPool(_pool).add_liquidity(
            _amounts,
            uint256(100000),
            false
        );
        return (poolTokensMinted);
    }

    function withdrawCRVPool(address _pool, uint256 _amount) private {
        address afETHPool = _pool;
        uint256[2] memory min_amounts;
        min_amounts[0] = 0;
        min_amounts[1] = 0;
        positions[msg.sender].curveBalances = 0;
        IAfEthPool(afETHPool).remove_liquidity(_amount, min_amounts);
    }

    // function mintBundleNft(
    //     uint256 cvxNftId,
    //     uint256 cvxAmount,
    //     uint256 balPoolTokens
    // ) private returns (uint256 id) {
    //     uint256 newBundleNftId = ++currentBundleNftId;
    //     // IAfBundle1155(bundleNFT).mint(
    //     //     cvxNftId,
    //     //     cvxAmount,
    //     //     newBundleNftId,
    //     //     balPoolTokens,
    //     //     address(this)
    //     // );
    //     // positions[currentDepositor] = newBundleNftId;
    //     // bundleNFtBalances[newBundleNftId] = balPoolTokens;
    //     return (newBundleNftId);
    // }

    // function burnBundleNFT(address user) private {
    //     uint256[2] memory ids;
    //     uint256[2] memory amounts;
    //     ids[0] = positions[user].bundleNFTID;
    //     ids[1] = positions[user].cvxNFTID;
    //     amounts[1] = positions[user].convexBalances;
    //     // IAfBundle1155(bundleNFT).burnBatch(address(this), ids, amounts);
    // }

    function mintCvxNft(
        address sender,
        uint256 _amountLocked
    ) private returns (uint256 balance, uint256 nftId) {
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

    // user selection in front-end:
    // True - user is transferred the 1155 NFT holding their CVX deposit
    // until CVX lockup period is over (16 weeks plus days to thursday 0000 UTC)
    // False - user pays fee to unlock their CVX and burn their NFT
    function withdrawCVXNft(bool _instantWithdraw) private {
        if (_instantWithdraw == true) {
            // TODO: start withdraw vlCVX
            IAfCVX1155(CVXNFT).safeTransferFrom(
                address(this),
                msg.sender,
                positions[msg.sender].cvxNFTID,
                positions[msg.sender].convexBalances,
                ""
            );
            console.log(
                "user balance of CVX NFT:",
                IAfCVX1155(CVXNFT).balanceOf(
                    msg.sender,
                    positions[msg.sender].cvxNFTID
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

    function updateCrvPool(address _crvPool) public onlyOwner {
        emit UpdateCrvPool(_crvPool, crvPool);
        crvPool = _crvPool;
    }

    receive() external payable {}
}
