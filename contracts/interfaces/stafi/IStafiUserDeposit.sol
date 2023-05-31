// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

abstract contract IStafiUserDeposit {
    function deposit() external virtual payable;
}
