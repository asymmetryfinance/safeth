// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../interfaces/IDerivative.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/ankr/AnkrStaker.sol";
import "../../interfaces/ankr/AnkrEth.sol";
import "../../interfaces/curve/IAnkrEthEthPool.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Storage.sol";

/// @title Derivative contract for ankr
/// @author Asymmetry Finance

contract Ankr is ERC165Storage, IDerivative, Initializable, OwnableUpgradeable {
    address public constant ANKR_ETH_ADDRESS =
        0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;
    address public constant ANKR_STAKER_ADDRESS =
        0x84db6eE82b7Cf3b47E8F19270abdE5718B936670;
    address public constant ANKR_ETH_POOL =
        0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2;

    uint256 public maxSlippage;

    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
        @notice - Function to initialize values for the contracts
        @dev - This replaces the constructor for upgradeable contracts
        @param _owner - owner of the contract which should be SafEth.sol
    */
    function initialize(address _owner) public initializer {
        require(_owner != address(0), "invalid address");
        _registerInterface(type(IDerivative).interfaceId);
        _transferOwnership(_owner);
        maxSlippage = (1 * 1e16); // 1%
    }

    function setChainlinkFeed(address _priceFeedAddress) public {
        // noop (for now until we fully test and integrate ankr)
    }

    /**
        @notice - Return derivative name
    */
    function name() external pure returns (string memory) {
        return "AnkrEth";
    }

    /**
        @notice - Owner only function to set max slippage for derivative
        @param _slippage - Amount of slippage to set in wei
    */
    function setMaxSlippage(uint256 _slippage) public onlyOwner {
        maxSlippage = _slippage;
    }

    /**
        @notice - Convert derivative into ETH
     */
    function withdraw(uint256 _amount) public onlyOwner {
        IERC20(ANKR_ETH_ADDRESS).approve(ANKR_ETH_POOL, _amount);
        uint256 price = ethPerDerivative();
        uint256 minOut = ((price * _amount) * (1e18 - maxSlippage)) / 1e36;
        IAnkrEthEthPool(ANKR_ETH_POOL).exchange(1, 0, _amount, minOut);
        // solhint-disable-next-line
        (bool sent, ) = address(msg.sender).call{value: address(this).balance}(
            ""
        );
        require(sent, "Failed to send Ether");
    }

    /**
        @notice - Owner only function to Deposit into derivative
        @dev - Owner is set to SafEth contract
     */
    function deposit() public payable onlyOwner returns (uint256) {
        uint256 ankrBalancePre = IERC20(ANKR_ETH_ADDRESS).balanceOf(
            address(this)
        );
        AnkrStaker(ANKR_STAKER_ADDRESS).stakeAndClaimAethC{value: msg.value}();
        uint256 ankrBalancePost = IERC20(ANKR_ETH_ADDRESS).balanceOf(
            address(this)
        );
        return ankrBalancePost - ankrBalancePre;
    }

    /**
        @notice - Get price of derivative in terms of ETH
     */
    function ethPerDerivative() public view returns (uint256) {
        return AnkrEth(ANKR_ETH_ADDRESS).sharesToBonds(1e18); // TODO chainlink needed here maybe????
    }

    /**
        @notice - Total derivative balance
     */
    function balance() external view returns (uint256) {
        return IERC20(ANKR_ETH_ADDRESS).balanceOf(address(this));
    }

    receive() external payable {}
}
