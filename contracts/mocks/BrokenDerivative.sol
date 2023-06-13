// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Storage.sol";
import "../interfaces/IDerivative.sol";

/// @title Derivative contract for sfrxETH
/// @author Asymmetry Finance
contract BrokenDerivative is
    ERC165Storage,
    IDerivative,
    Initializable,
    OwnableUpgradeable
{
    address public constant SFRX_ETH_ADDRESS =
        0xac3E018457B222d93114458476f3E3416Abbe38F;
    address public constant FRX_ETH_ADDRESS =
        0x5E8422345238F34275888049021821E8E08CAa1f;
    address public constant FRX_ETH_CRV_POOL_ADDRESS =
        0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
    address public constant FRX_ETH_MINTER_ADDRESS =
        0xbAFA44EFE7901E04E39Dad13167D089C559c1138;

    uint256 public maxSlippage;
    error BrokenDerivativeError();

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
    function initialize(address _owner) external initializer {
        _registerInterface(type(IDerivative).interfaceId);
        _transferOwnership(_owner);
        maxSlippage = (1 * 1e16); // 1%
    }

    function setChainlinkFeed(address _priceFeedAddress) public onlyOwner {
        // noop (for now until we fully test and integrate ankr)
    }

    /**
        @notice - Return derivative name
    */
    function name() public pure returns (string memory) {
        return "Broken Derivative";
    }

    /**
        @notice - Owner only function to set max slippage for derivative
    */
    function setMaxSlippage(uint256 _slippage) external onlyOwner {
        maxSlippage = _slippage;
    }

    /**
        @notice - Owner only function to Convert derivative into ETH
        @dev - Owner is set to SafEth contract
     */
    function withdraw(uint256 /* _amount */) external view onlyOwner {
        revert BrokenDerivativeError();
    }

    /**
        @notice - Owner only function to Deposit into derivative
        @dev - Owner is set to SafEth contract
     */
    function deposit() external payable onlyOwner returns (uint256) {
        revert BrokenDerivativeError();
    }

    /**
        @notice - Get price of derivative in terms of ETH
     */
    function ethPerDerivative(bool) public pure returns (uint256) {
        return 1e18;
    }

    /**
        @notice - Total derivative balance
     */
    function balance() public pure returns (uint256) {
        return 1e18;
    }

    receive() external payable {}
}
