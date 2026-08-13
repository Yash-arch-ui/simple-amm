//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";
import {AMMLibrary} from "../src/AMMLibrary.sol";
import {TWAPOracle} from "../src/TWAPOracle.sol";
import {FixedWindowTWAP} from "../src/FixedWindowTWAP.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// @title TWAPAttackTest
/// @notice Simulation of an attacker trying to manipulate the TWAP price.
///
/// Setup: pool holds 500 token0 / 50 token1  ->  true price0 (token1 per token0) = 0.1
/// Attack: attacker dumps 900 token0 into the pool, crashing price0 to ~0.0128 (-87%).
///
/// The key question: how much does the TWAP move? Answer: proportional to the FRACTION
/// of the observation window the fake price was held. Holding for 2s of a 1h window
/// barely registers; holding for 30min moves it by ~40%.
contract TWAPAttackTest is Test {
    MockERC20 token0;
    MockERC20 token1;
    SimpleAMM amm;

    FixedWindowTWAP oracle1H; // 1-hour window   -> recommended for critical protocols
    FixedWindowTWAP oracle1M; // 1-minute window -> sensitive to brief pumps
    FixedWindowTWAP oracle5S; // 5-second window -> extremely manipulable
    TWAPOracle naiveOracle;   // the naive oracle from TWAPOracle.sol (no projection)

    address user = makeAddr("user");
    address attacker = makeAddr("attacker");

    uint256 constant RESERVE0 = 500 ether;
    uint256 constant RESERVE1 = 50 ether;
    uint256 constant TRUE_PRICE0 = 0.1e18; // reserve1/reserve0, 1e18 scaled
    uint256 constant ATTACK_IN = 900 ether;

    function setUp() public {
        vm.warp(1_000_000); // fixed baseline timestamp

        token0 = new MockERC20("Token0", "TK0");
        token1 = new MockERC20("Token1", "TK1");
        amm = new SimpleAMM(address(token0), address(token1));

        token0.mint(user, 10_000 ether);
        token1.mint(user, 10_000 ether);
        token0.mint(attacker, 10_000 ether);
        token1.mint(attacker, 10_000 ether);

        vm.startPrank(user);
        token0.approve(address(amm), RESERVE0);
        token1.approve(address(amm), RESERVE1);
        amm.addLiquidity(RESERVE0, RESERVE1);
        vm.stopPrank();

        oracle1H = new FixedWindowTWAP(address(amm), 1 hours);
        oracle1M = new FixedWindowTWAP(address(amm), 60);
        oracle5S = new FixedWindowTWAP(address(amm), 5);
        naiveOracle = new TWAPOracle(address(amm));
    }

    /// @notice Deploy an isolated pool + oracle (same reserves as setUp), for tests
    ///         that need a clean, controlled window on a fresh timeline.
    function _deployPoolAndOracle(
        uint32 windowSize
    ) internal returns (SimpleAMM pool, FixedWindowTWAP oracle, MockERC20 t0token, MockERC20 t1token) {
        t0token = new MockERC20("Token0", "TK0");
        t1token = new MockERC20("Token1", "TK1");
        t0token.mint(user, 10_000 ether);
        t1token.mint(user, 10_000 ether);
        t0token.mint(attacker, 10_000 ether);
        t1token.mint(attacker, 10_000 ether);

        pool = new SimpleAMM(address(t0token), address(t1token));

        vm.startPrank(user);
        t0token.approve(address(pool), RESERVE0);
        t1token.approve(address(pool), RESERVE1);
        pool.addLiquidity(RESERVE0, RESERVE1);
        vm.stopPrank();

        oracle = new FixedWindowTWAP(address(pool), windowSize);
    }

    /// @notice The attack: dump ATTACK_IN of `t0token` into `pool`, crashing price0 by ~87%.
    function _attackOn(SimpleAMM pool, MockERC20 t0token) internal returns (uint256 spotAfter) {
        vm.startPrank(attacker);
        t0token.approve(address(pool), ATTACK_IN);
        pool.swap(ATTACK_IN, address(t0token));
        vm.stopPrank();
        spotAfter = AMMLibrary.getSpotPrice(pool.reserve0(), pool.reserve1());
    }

    // ------------------------------------------------------------------ //
    //  Scenario A: brief pump (2 seconds of a 1-hour window)             //
    // ------------------------------------------------------------------ //
    function testBriefPump2s_1HourWindow() public {
        vm.warp(block.timestamp + 3598);
        uint256 spotAfter = _attackOn(amm, token0); // crash price at t+3598
        vm.warp(block.timestamp + 2); // ...hold for 2s -> t+3600
        oracle1H.update();

        uint256 twap = oracle1H.price0Average();
        console.log("--- 2s pump vs 1h window ---");
        console.log("spot price after attack :", spotAfter);
        console.log("1h TWAP after 2s pump   :", twap);

        // spot collapsed by more than 80%
        assertLt(spotAfter, TRUE_PRICE0 / 5);
        // but TWAP stayed within 1% of the true price (~0.09995 vs 0.1)
        assertGt(twap, (TRUE_PRICE0 * 99) / 100);

        // end-to-end: consult() converts amounts at the TWAP price (~9.995 for 100 in)
        uint256 amountOut = oracle1H.consult(address(token0), 100 ether);
        assertApproxEqRel(amountOut, 9.995 ether, 0.001e18);
    }

    // ------------------------------------------------------------------ //
    //  Scenario B: sustained pump (30 minutes of a 1-hour window)        //
    // ------------------------------------------------------------------ //
    function testSustainedPump30min_1HourWindow() public {
        vm.warp(block.timestamp + 1800);
        uint256 spotAfter = _attackOn(amm, token0); // crash price at t+1800
        vm.warp(block.timestamp + 1800); // ...hold for 30min -> t+3600
        oracle1H.update();

        uint256 twap = oracle1H.price0Average();
        console.log("--- 30min pump vs 1h window ---");
        console.log("spot price after attack :", spotAfter);
        console.log("1h TWAP after 30min pump:", twap);

        // TWAP now moved hard: below 60% of the true price (~0.0564 vs 0.1)
        assertLt(twap, (TRUE_PRICE0 * 60) / 100);
        // but still well above the crashed spot price
        assertGt(twap, spotAfter * 4);
    }

    // ------------------------------------------------------------------ //
    //  Scenario C: window size determines vulnerability                  //
    // ------------------------------------------------------------------ //
    function testWindowSizeMatters_Same2sPump() public {
        // 1-minute window, attack at t+58, hold 2s -> update at t+60
        (SimpleAMM pool1M, FixedWindowTWAP oracle1m, MockERC20 t0_1M, ) = _deployPoolAndOracle(60);
        vm.warp(block.timestamp + 58);
        _attackOn(pool1M, t0_1M);
        vm.warp(block.timestamp + 2);
        oracle1m.update();
        uint256 twap1M = oracle1m.price0Average();

        // 5-second window, attack at t+3, hold 2s -> update at t+5
        (SimpleAMM pool5S, FixedWindowTWAP oracle5s, MockERC20 t0_5S, ) = _deployPoolAndOracle(5);
        vm.warp(block.timestamp + 3);
        _attackOn(pool5S, t0_5S);
        vm.warp(block.timestamp + 2);
        oracle5s.update();
        uint256 twap5S = oracle5s.price0Average();

        console.log("--- same 2s pump, different windows ---");
        console.log("1m window TWAP :", twap1M); // ~0.0971 (2.9% off)
        console.log("5s window TWAP :", twap5S); // ~0.0651 (35% off)

        // 1-minute window still holds up reasonably
        assertGt(twap1M, (TRUE_PRICE0 * 95) / 100);
        // 5-second window is badly skewed
        assertLt(twap5S, (TRUE_PRICE0 * 70) / 100);
        assertGt(twap5S, (TRUE_PRICE0 * 60) / 100);
    }

    // ------------------------------------------------------------------ //
    //  Scenario D: why the naive oracle (TWAPOracle.sol) is different    //
    // ------------------------------------------------------------------ //

    /// A quiet market: no trade between two update() calls -> the naive oracle
    /// measures timeElapsed = 0 (it reads the PAIR's last-trade timestamp, not
    /// block.timestamp) and reverts. The FixedWindowTWAP handles it fine because
    /// it projects the current spot price forward to block.timestamp.
    function testNaiveOracleRevertsInQuietMarket() public {
        vm.warp(block.timestamp + 100); // no trades in between
        vm.expectRevert("NO_TIME_ELAPSED");
        naiveOracle.update(); // reverts!

        // the fixed-window oracle has no such problem
        oracle1M.update();
        assertEq(oracle1M.price0Average(), TRUE_PRICE0);
    }

    /// consult() before any successful update() reverts instead of returning 0.
    function testConsultRevertsBeforeUpdate() public {
        vm.expectRevert("NOT_UPDATED");
        oracle1H.consult(address(token0), 1 ether);
    }

    /// Attacker holds the fake price WITHOUT trading again. The naive oracle's window
    /// ends at the attack trade itself, so it reports the PRE-attack price and the 2s
    /// of held fake price contributes nothing. It looks "resistant" but only because
    /// it is stale: it cannot see any price unless a trade banks it.
    function testNaiveOracleIsStaleDuringHold() public {
        vm.warp(block.timestamp + 58);
        uint256 spotAfter = _attackOn(amm, token0);
        vm.warp(block.timestamp + 2);

        naiveOracle.update();
        uint256 twap = naiveOracle.price0Average();
        console.log("--- naive oracle during 2s hold ---");
        console.log("spot price after attack :", spotAfter);
        console.log("naive TWAP              :", twap);

        // reports the pre-attack price as if nothing happened
        assertEq(twap, TRUE_PRICE0);

        // the proper fixed-window oracle includes the 2s at the fake price
        oracle1M.update();
        uint256 twapProper = oracle1M.price0Average();
        assertLt(twapProper, TRUE_PRICE0);
    }
}
