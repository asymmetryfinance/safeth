// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

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

    uint256 totalEthAmount;

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

        // No need to transfer 'want' token as ETH has already been sent
        // asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        shares = previewWithdraw(assets);
        beforeWithdraw(assets);

        //_burn(owner, shares);

        //emit Withdraw(msg.sender, receiver, owner, assets, shares);

        // Send deposited ETH back to user
        //(bool sent, ) = receiver.call{value: assets}("");
        //require(sent, "Failed to send Ether");
    }

    // Primary entrance into Golden Ratio Vault
    // vault can receive ether and wrap as underlying token (WETH)
    function _deposit() public payable returns (uint256 shares) {
        // Require 48 ETH sent to contract to deposit in Vault
        require(msg.value == 48e18, "Invalid Deposit");
        // update balance of ETH deposited in GR Vault
        totalEthAmount += msg.value;
        // update count of funds in vault
        weth.deposit{value: msg.value}();
        //weth.approve(address(this), 1e18);
        //wethToken.approve(address(vault), 1e18);
        uint256 sharesMinted = deposit(msg.value, msg.sender);
        return sharesMinted;
    }

    /// @notice Total amount of the underlying asset that
    /// is "managed" by Vault.
    function totalAssets() public view override returns (uint256) {
        return totalEthAmount;
    }

    // Withdraw any tokens that might airdropped or mistakenly be send to this address
    function saveTokens(address _token, uint _amount) external {
        ERC20(_token).transfer(msg.sender, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    // Vault has WETH
    // Reverse strat logic to repay initial deposit
    function beforeWithdraw(uint256 assets) internal {
        // unwrap amount of weth left that's sent back to vault
        // eth + weth sent back
        // could also unwrap all and send back only eth to vault
        //weth.withdraw(assets);
        IController(controller).withdraw(address(token), msg.sender, assets);
        (bool sent, ) = msg.sender.call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }

    // Vault has WETH
    // Trigger strategy
    function afterDeposit(uint256 assets) internal {
        // deposit weth in strategy
        token.safeTransferFrom(
            address(this),
            IController(controller).getStrategy(address(WETH9)),
            assets
        );
        // Begin strategy deposit sequence
        IController(controller).deposit(address(token), msg.sender, assets);
    }

    function getName() external pure returns (string memory) {
        return "Golden Ratio Vault";
    }

    // Payable function to receive ETH after unwrapping WETH
    // and receive ETH from strategy
    receive() external payable {}
}
