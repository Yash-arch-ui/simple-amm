// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20}  from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AMMLibrary} from "./AMMLibrary.sol";

contract SimpleAMM is ERC20 {

    address public token0;
    address public token1;
    uint256 public reserve0;
    uint256 public reserve1;

    uint256 private unlocked = 1;

    modifier lock() {
        require(unlocked == 1, "LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor(address _token0, address _token1) ERC20("LP Token", "LP") {
        require(_token0 != address(0), "Invalid token0");
        require(_token1 != address(0), "Invalid token1");
        require(_token0 != _token1,    "Tokens must be different");
        token0 = _token0;
        token1 = _token1;
    }

    function addLiquidity(
        uint256 amount0,
        uint256 amount1
    ) external lock returns (uint256 lpAmount) {
        require(amount0 > 0 && amount1 > 0, "Amounts must be greater than zero");

        IERC20(token0).transferFrom(msg.sender, address(this), amount0);
        IERC20(token1).transferFrom(msg.sender, address(this), amount1);

        lpAmount = AMMLibrary.getLPAmount(
            amount0, amount1,
            reserve0, reserve1,
            totalSupply()
        );

        require(lpAmount > 0, "Insufficient liquidity provided");
        _mint(msg.sender, lpAmount);

        reserve0 = IERC20(token0).balanceOf(address(this));
        reserve1 = IERC20(token1).balanceOf(address(this));
    }

    function swap(
        uint256 amountIn,
        address tokenIn
    ) external lock returns (uint256 amountOut) {
        require(tokenIn == token0 || tokenIn == token1, "Invalid token");
        require(amountIn > 0, "Amount must be greater than zero");

        address tokenOut;
        uint256 reserveIn;
        uint256 reserveOut;

        if (tokenIn == token0) {
            tokenOut   = token1;
            reserveIn  = reserve0;
            reserveOut = reserve1;
        } else {
            tokenOut   = token0;
            reserveIn  = reserve1;
            reserveOut = reserve0;
        }

        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        amountOut = AMMLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut > 0, "Insufficient output amount");
        IERC20(tokenOut).transfer(msg.sender, amountOut);
        reserve0 = IERC20(token0).balanceOf(address(this));
        reserve1 = IERC20(token1).balanceOf(address(this));
    }

    function removeLiquidity(
        uint256 lpAmount
    ) external lock returns (uint256 amount0, uint256 amount1) {
        require(lpAmount > 0, "Amount must be greater than zero");
        require(balanceOf(msg.sender) >= lpAmount, "Insufficient LP balance");

        (amount0, amount1) = AMMLibrary.getWithdrawAmounts(
            lpAmount,
            reserve0, reserve1,
            totalSupply()
        );

        require(amount0 > 0 && amount1 > 0, "Insufficient liquidity burned");

        _burn(msg.sender, lpAmount);

        IERC20(token0).transfer(msg.sender, amount0);
        IERC20(token1).transfer(msg.sender, amount1);

        reserve0 = IERC20(token0).balanceOf(address(this));
        reserve1 = IERC20(token1).balanceOf(address(this));
    }

    function getReserves() external view returns (uint256, uint256) {
        return (reserve0, reserve1);
    }

    function quoteAmountOut(
        uint256 amountIn,
        address tokenIn
    ) external view returns (uint256) {
        uint256 reserveIn  = tokenIn == token0 ? reserve0 : reserve1;
        uint256 reserveOut = tokenIn == token0 ? reserve1 : reserve0;
        return AMMLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function quoteAmountIn(
        uint256 amountOut,
        address tokenIn
    ) external view returns (uint256) {
        uint256 reserveIn  = tokenIn == token0 ? reserve0 : reserve1;
        uint256 reserveOut = tokenIn == token0 ? reserve1 : reserve0;
        return AMMLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function quotePriceImpact(
        uint256 amountIn,
        address tokenIn
    ) external view returns (uint256) {
        uint256 reserveIn  = tokenIn == token0 ? reserve0 : reserve1;
        uint256 reserveOut = tokenIn == token0 ? reserve1 : reserve0;
        return AMMLibrary.getPriceImpact(amountIn, reserveIn, reserveOut);
    }
}