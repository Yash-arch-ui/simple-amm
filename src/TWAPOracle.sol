// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISimpleAMM {
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
    function blockTimestampLast() external view returns (uint32);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

contract TWAPOracle {
    ISimpleAMM public immutable amm;

    uint256 public lastPrice0Cumulative;
    uint256 public lastPrice1Cumulative;
    uint32 public lastTimestamp;
    uint256 public price0Average;
    uint256 public price1Average;

    event OracleUpdated(uint256 price0Average, uint256 price1Average);

    constructor(address _amm) {

        amm = ISimpleAMM(_amm);

        lastPrice0Cumulative = amm.price0CumulativeLast();
        lastPrice1Cumulative = amm.price1CumulativeLast();
        lastTimestamp = amm.blockTimestampLast();

    }

    function update() external {
        uint256 currentPrice0Cumulative = amm.price0CumulativeLast();

        uint256 currentPrice1Cumulative = amm.price1CumulativeLast();

        uint32 currentTimestamp = amm.blockTimestampLast();

        uint32 timeElapsed = currentTimestamp - lastTimestamp;

        require(timeElapsed > 0, "NO_TIME_ELAPSED");

        price0Average =
            (currentPrice0Cumulative - lastPrice0Cumulative) /
            timeElapsed;

        price1Average =
            (currentPrice1Cumulative - lastPrice1Cumulative) /
            timeElapsed;

        lastPrice0Cumulative = currentPrice0Cumulative;
        lastPrice1Cumulative = currentPrice1Cumulative;
        lastTimestamp = currentTimestamp;

        emit OracleUpdated(price0Average, price1Average);
    }

    function consult(
        address token,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        if (token == amm.token0()) {
            amountOut = (amountIn * price0Average) / 1e18;
        } else if (token == amm.token1()) {
            amountOut = (amountIn * price1Average) / 1e18;
        } else {
            revert("INVALID_TOKEN");
        }
    }
}
