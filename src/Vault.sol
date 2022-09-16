pragma solidity ^0.8;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "./interfaces/IWETH.sol";

contract Vault is ERC4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    ERC20 public immutable token;

    uint256 sharesMinted;

    // WETH token address
    // https://docs.uniswap.org/protocol/reference/deployments
    address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IWETH private weth = IWETH(WETH9);

    constructor(
        address _token,
        string memory _name,
        string memory _symbol
    ) ERC4626(ERC20(_token), _name, _symbol) {
        token = ERC20(_token);
    }

    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        // no need to transfer as contract already holds ETH, wraps WETH internally
        // asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    /**
     * @notice calculate ETH to withdraw from strategy given a ownership proportion
     * @param _shares shares
     * @param _strategyCollateralAmount amount of collateral in strategy
     * @return amount of ETH allowed to withdraw
     */
    function _calcEthToWithdraw(
        uint256 _shares,
        uint256 _strategyCollateralAmount
    ) internal view returns (uint256) {
        return _strategyCollateralAmount * (_shares / (totalAssets()));
    }

    // ACCOUNTING LOGIC

    /// @notice Total amount of the underlying asset that
    /// is "managed" by Vault.
    function totalAssets() public view override returns (uint256) {
        return IERC20(WETH9).balanceOf(address(this));
    }

    // DEPOSIT/WITHDRAWAL LIMIT LOGIC

    /// @notice maximum amount of assets that can be deposited.
    function maxDeposit(address) public view override returns (uint256) {
        return type(uint256).max;
    }

    /// @notice maximum amount of shares that can be minted.
    function maxMint(address) public view override returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Maximum amount of assets that can be withdrawn.
    function maxWithdraw(address owner) public view override returns (uint256) {
        return convertToAssets(balanceOf[owner]);
    }

    /// @notice Maximum amount of shares that can be redeemed.
    function maxRedeem(address owner) public view override returns (uint256) {
        return balanceOf[owner];
    }

    // INTERNAL HOOKS LOGIC

    // Vault has WETH
    // Reverse strat logic to repay initial deposit
    function beforeWithdraw(uint256 assets, uint256 shares) internal override {}

    // Vault has WETH
    // Trigger strategy
    function afterDeposit(uint256 assets, uint256 shares) internal override {}

    // deal with received ether and call deposit function
    function depositWeth() public returns (uint256 shares) {
        weth.deposit{value: 1e18}();
        //weth.approve(address(this), 1e18);
        //wethToken.approve(address(vault), 1e18);
        sharesMinted = deposit(1e18, msg.sender);
        return sharesMinted;
    }

    // vault can receive ether and wrap as underlying token (WETH)
    receive() external payable {
        depositWeth();
    }

    // get shares minted
    function getShares() public view returns (uint256 shares) {
        return sharesMinted;
    }
}
