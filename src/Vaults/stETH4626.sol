// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IStETH} from "../interfaces/lido/IStETH.sol";

contract StETH4626 is ERC4626 {
    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using FixedPointMathLib for uint256;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(ERC20 asset_)
        ERC4626(asset_, "ERC4626-Wrapped Lido stETH", "wlstETH")
    {}

    /// -----------------------------------------------------------------------
    /// Getters
    /// -----------------------------------------------------------------------

    function stETH() public view returns (IStETH) {
        return IStETH(address(asset));
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    function totalAssets() public view virtual override returns (uint256) {
        return stETH().balanceOf(address(this));
    }

    function convertToShares(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 supply = stETH().totalSupply();

        return
            supply == 0
                ? assets
                : assets.mulDivDown(stETH().getTotalShares(), supply);
    }

    function convertToAssets(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 totalShares = stETH().getTotalShares();

        return
            totalShares == 0
                ? shares
                : shares.mulDivDown(stETH().totalSupply(), totalShares);
    }

    function previewMint(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 totalShares = stETH().getTotalShares();

        return
            totalShares == 0
                ? shares
                : shares.mulDivUp(stETH().totalSupply(), totalShares);
    }

    function previewWithdraw(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 supply = stETH().totalSupply();

        return
            supply == 0
                ? assets
                : assets.mulDivUp(stETH().getTotalShares(), supply);
    }
}
