//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SimpleAMM} from "./SimpleAMM.sol";
import {AMMLibrary} from "./AMMLibrary.sol";
import {IUniswapV2Callee} from "./IUniswapV2Callee.sol";

contract FlashLoanReceiver is IUniswapV2Callee {
    address public immutable owner;
    address public immutable pair;
    uint256 public profit;

    constructor(address _pair) {
        owner = msg.sender;
        pair = _pair;
    }

    function flashBorrow(uint256 amount0Out, uint256 amount1Out, bytes calldata data) external {
        require(msg.sender == owner, "NOT_OWNER");
        SimpleAMM(pair).swap(amount0Out, amount1Out, address(this), data);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == pair, "NOT_PAIR");
        require(sender == address(this), "NOT_BORROWER");
        (address target, uint256 minProfit) = abi.decode(data, (address, uint256));
        SimpleAMM pool = SimpleAMM(pair);
        if (amount0 > 0) {
            IERC20(pool.token0()).approve(target, amount0);
            SimpleAMM(target).swap(amount0, pool.token0());
            uint256 repay = AMMLibrary.getAmountIn(amount0, pool.reserve1(), pool.reserve0());
            uint256 balance = IERC20(pool.token1()).balanceOf(address(this));
            require(balance >= repay + minProfit, "UNPROFITABLE");
            IERC20(pool.token1()).transfer(pair, repay);
            profit += balance - repay;
        }
        if (amount1 > 0) {
            IERC20(pool.token1()).approve(target, amount1);
            SimpleAMM(target).swap(amount1, pool.token1());
            uint256 repay = AMMLibrary.getAmountIn(amount1, pool.reserve0(), pool.reserve1());
            uint256 balance = IERC20(pool.token0()).balanceOf(address(this));
            require(balance >= repay + minProfit, "UNPROFITABLE");
            IERC20(pool.token0()).transfer(pair, repay);
            profit += balance - repay;
        }
    }

    function withdraw(address token) external {
        require(msg.sender == owner, "NOT_OWNER");
        IERC20(token).transfer(owner, IERC20(token).balanceOf(address(this)));
    }
}
