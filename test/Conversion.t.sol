// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Conversion.sol";
import "./mocks/MockV3Aggregator.sol";

contract ConversionTest is Test {
    Conversion public conversion;

    function setUp() public {
        conversion = new Conversion();
    }

    function testConversionReturnsStartingValue() public {
        int256 price = conversion.getLatestPrice();
        emit log_int(price);
    }
}
