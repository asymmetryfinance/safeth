import "@openzeppelin/contracts/utils/introspection/ERC165Storage.sol";
import "../../interfaces/IDerivative.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract DerivativeBase is ERC165Storage, IDerivative, Initializable, OwnableUpgradeable {
    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function checkSlippageAndWithdraw(uint256 _price, uint256 _amount, uint256 _maxSlippage, uint256 _received, bool _isDeposit) internal {
        uint256 minOut = _isDeposit ? ((_amount * (1e18 - _maxSlippage)) / _price) : (((_price * _amount) * (1e18 - _maxSlippage)) / 1e36);
        require(_received >= minOut, "Slippage too high");
        if(!_isDeposit) {
            (bool sent, ) = address(msg.sender).call{value: _received}("");
            require(sent, "Failed to send Ether");
        }
    }

    function init(address _owner) public {
        require(_owner != address(0), "invalid address");
        _registerInterface(type(IDerivative).interfaceId);
        _transferOwnership(_owner);
    }


    receive() external payable {}
}