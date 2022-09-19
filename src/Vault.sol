pragma solidity ^0.8;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IController.sol";
import "forge-std/console.sol";

contract Vault is ERC4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    address public controller;
    address public governance;

    ERC20 public immutable token;

    uint256 sharesMinted;

    uint256 totalEthAmount;

    address depositor;

    // WETH token address
    // https://docs.uniswap.org/protocol/reference/deployments
    address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IWETH private weth = IWETH(WETH9);

    constructor(
        address _token,
        string memory _name,
        string memory _symbol,
        address _governance,
        address _controller
    ) ERC4626(ERC20(_token), _name, _symbol) {
        token = ERC20(_token);
        governance = _governance;
        controller = _controller;
    }

    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets);
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
    function afterDeposit(uint256 assets) internal {
        // deposit weth in strategy
        token.safeTransferFrom(
            address(this),
            IController(controller).getStrategy(address(WETH9)),
            assets
        );
        // begin strategy deposit sequence w/ new weth deposit
        IController(controller).deposit(address(token), depositor, assets);
    }

    // Primary entrance into Golden Ratio Vault
    // vault can receive ether and wrap as underlying token (WETH)
    function _deposit() public payable returns (uint256 shares) {
        require(msg.value == 48e18, "Invalid Deposit");
        // update count of deposited ETH
        totalEthAmount += msg.value;
        // update count of funds in vault
        weth.deposit{value: msg.value}();
        //weth.approve(address(this), 1e18);
        //wethToken.approve(address(vault), 1e18);
        depositor = msg.sender;
        sharesMinted = deposit(msg.value, depositor);
        return sharesMinted;
    }

    // get shares minted
    function getShares() public view returns (uint256 shares) {
        return sharesMinted;
    }

    function getTotalEthAmount() public returns (uint256) {
        return (totalEthAmount);
    }
}
