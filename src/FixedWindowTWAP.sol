//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISimpleAMM {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
    function blockTimestampLast() external view returns (uint32);
    function getReserves() external view returns (uint256 reserve0, uint256 reserve1);
}

/// @title FixedWindowTWAP
/// @notice A Uniswap V2-style Time-Weighted Average Price oracle with a FIXED window size.
///
/// The pair (SimpleAMM) banks `price * timeElapsed` into `price0CumulativeLast` /
/// `price1CumulativeLast` on every trade. This oracle:
///   1. adds the *current spot price projected forward* to `block.timestamp` (this is the
///      key piece the naive oracle in TWAPOracle.sol is missing), and
///   2. computes the average over a fixed window by dividing the cumulative delta
///      by the elapsed time.
///
/// `update()` may be called once at least `windowSize` seconds have elapsed; calling it
/// later yields a longer (still valid) window. Consumers should call `update()` at least
/// once before relying on `consult()`, otherwise `consult()` reverts.
contract FixedWindowTWAP {
    ISimpleAMM public immutable amm;
    uint32 public immutable windowSize; // e.g. 1 hours

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint32 public blockTimestampLast;

    uint256 public price0Average; // scaled by 1e18 (token1 per token0)
    uint256 public price1Average; // scaled by 1e18 (token0 per token1)
    bool public isInitialized; // true after the first successful update()

    constructor(address _amm, uint32 _windowSize) {
        require(_windowSize > 0, "INVALID_WINDOW");
        amm = ISimpleAMM(_amm);
        windowSize = _windowSize;
        // Seed the checkpoint with the cumulative projected to "now", so the first
        // `update()` after `windowSize` seconds yields a clean full-window average.
        (price0CumulativeLast, price1CumulativeLast, blockTimestampLast) = _currentCumulative();
    }

    /// @notice Recompute the TWAP over the elapsed period. Reverts if less than
    ///         `windowSize` seconds have passed since the last update.
    function update() external {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = _currentCumulative();

        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        require(timeElapsed >= windowSize, "PERIOD_NOT_ELAPSED");

        price0Average = (price0Cumulative - price0CumulativeLast) / timeElapsed;
        price1Average = (price1Cumulative - price1CumulativeLast) / timeElapsed;

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
        isInitialized = true;
    }

    /// @notice Convert `amountIn` of `token` into the other token at the TWAP price.
    function consult(address token, uint256 amountIn) external view returns (uint256 amountOut) {
        require(isInitialized, "NOT_UPDATED");
        if (token == amm.token0()) {
            amountOut = (amountIn * price0Average) / 1e18;
        } else if (token == amm.token1()) {
            amountOut = (amountIn * price1Average) / 1e18;
        } else {
            revert("INVALID_TOKEN");
        }
    }

    /// @notice Pair cumulative price with the CURRENT spot price projected forward to
    ///         `block.timestamp`. Between trades the reserves (and therefore the price)
    ///         do not change, so projecting `spotPrice * timeSinceLastTrade` is exact.
    function _currentCumulative()
        internal
        view
        returns (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp)
    {
        blockTimestamp = uint32(block.timestamp);
        price0Cumulative = amm.price0CumulativeLast();
        price1Cumulative = amm.price1CumulativeLast();

        (uint256 reserve0, uint256 reserve1) = amm.getReserves();
        uint32 timeElapsed = blockTimestamp - amm.blockTimestampLast();
        if (timeElapsed > 0 && reserve0 > 0 && reserve1 > 0) {
            price0Cumulative += ((reserve1 * 1e18) / reserve0) * timeElapsed;
            price1Cumulative += ((reserve0 * 1e18) / reserve1) * timeElapsed;
        }
    }
}
