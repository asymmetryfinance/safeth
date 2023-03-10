// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IDerivative {

    function name() external pure returns(string memory);

    function deposit() external payable returns (uint256);

    function withdraw(uint256 amount) external;

    function ethPerDerivative(uint256 amount) external view returns (uint256);

    function totalEthValue() external view returns (uint256);

    function balance() external view returns (uint256);

    function setMaxSlippage(uint256 slippage) external;
}
