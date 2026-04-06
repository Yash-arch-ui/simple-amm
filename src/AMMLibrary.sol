// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library AMMLibrary {
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0,                          "Insufficient input amount");
        require(reserveIn > 0 && reserveOut > 0,       "Insufficient liquidity");

        uint256 numerator   = amountIn * 997 * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountIn * 997;
        amountOut           = numerator / denominator;
    }
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {

        require(amountOut > 0,"Insufficient output amount");
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
        uint256 numerator   = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
         amountIn= (numerator / denominator) + 1;  // +1 rounds up
    }
    function getSpotPrice(
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 price) {
        require(reserveIn > 0, "No liquidity");
        price = (reserveOut * 1e18) / reserveIn;   
    }
    function getPriceImpact(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 impact) {
        uint256 amountOut    = getAmountOut(amountIn, reserveIn, reserveOut);
        uint256 newReserveIn  = reserveIn  + amountIn;
        uint256 newReserveOut = reserveOut - amountOut;

        uint256 oldPrice = (reserveOut  * 1e18) / reserveIn;
        uint256 newPrice = (newReserveOut * 1e18) / newReserveIn;
        impact = ((oldPrice - newPrice) * 1e18) / oldPrice;
    }

    function getLPAmount(
        uint256 amount0,
        uint256 amount1,
        uint256 reserve0,
        uint256 reserve1,
        uint256 totalSupply
    ) internal pure returns (uint256 lpAmount) {
        if (totalSupply == 0) {
            lpAmount = sqrt(amount0 * amount1);    // first deposit
        } else {
            lpAmount = min(
                amount0 * totalSupply / reserve0,
                amount1 * totalSupply / reserve1
            );
        }
    }
    function getWithdrawAmounts(
        uint256 lpAmount,
        uint256 reserve0,
        uint256 reserve1,
        uint256 totalSupply
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        amount0 = (lpAmount * reserve0) / totalSupply;
        amount1 = (lpAmount * reserve1) / totalSupply;
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}