// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20}     from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SimpleAMM}  from "./SimpleAMM.sol";
import {AMMLibrary} from "./AMMLibrary.sol";

contract AMMRouter {

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 minAmountOut,
        address tokenIn,
        address amm
    ) external returns (uint256 amountOut) {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).approve(amm, amountIn);
        amountOut = SimpleAMM(amm).swap(amountIn, tokenIn);
        require(amountOut >= minAmountOut, "INSUFFICIENT_OUTPUT_AMOUNT");
    }

    function multiHop(
        uint256 amountIn,
        uint256 minAmountOut,
        address[] calldata path,
        address[] calldata pairs
    ) external returns (uint256 finalAmountOut) {
        require(path.length >= 2,                "Invalid path");
        require(pairs.length == path.length - 1, "Invalid pairs length");

        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        uint256 currentAmount = amountIn;

        for (uint256 i = 0; i < path.length - 1; i++) {
            address tokenIn = path[i];
            address pair    = pairs[i];

            (uint256 reserve0, uint256 reserve1) = SimpleAMM(pair).getReserves();
            address token0 = SimpleAMM(pair).token0();

            uint256 reserveIn  = tokenIn == token0 ? reserve0 : reserve1;
            uint256 reserveOut = tokenIn == token0 ? reserve1 : reserve0;

            uint256 amountOut = AMMLibrary.getAmountOut(
                currentAmount,
                reserveIn,
                reserveOut
            );

            require(amountOut > 0, "Insufficient output in hop");

            IERC20(tokenIn).approve(pair, currentAmount);
            SimpleAMM(pair).swap(currentAmount, tokenIn);

            currentAmount = amountOut;
        }

        finalAmountOut = currentAmount;
        require(finalAmountOut >= minAmountOut, "Slippage too high");

        IERC20(path[path.length - 1]).transfer(msg.sender, finalAmountOut);
    }
}