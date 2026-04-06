//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";
import {AMMRouter} from "../src/AMMRouter.sol";
import {AMMLibrary} from "../src/AMMLibrary.sol";
import {MockERC20} from "../src/MockERC20.sol";

contract AMMTest is Test {
    MockERC20 token0;
    MockERC20 token1;
    SimpleAMM amm;
    AMMRouter router;

    address user = makeAddr("user");
    address userB = makeAddr("userB");
    address attacker = makeAddr("attacker");

    function setUp() public {
        token0 = new MockERC20("Token0", "TK0");
        token1 = new MockERC20("Token1", "TK1");
        amm = new SimpleAMM(address(token0), address(token1));
        router = new AMMRouter();

        token0.mint(user, 10000 ether);
        token1.mint(user, 10000 ether);
        token0.mint(userB, 10000 ether);
        token1.mint(userB, 10000 ether);
        token0.mint(attacker, 10000 ether);
        token1.mint(attacker, 10000 ether);

        vm.startPrank(user);
        token0.approve(address(amm), 500 ether);
        token1.approve(address(amm), 50 ether);
        amm.addLiquidity(500 ether, 50 ether);
        vm.stopPrank();
    }

    function testAddLiquidityFirstDeposit() public {
        vm.startPrank(user);
        SimpleAMM freshAMM = new SimpleAMM(address(token0), address(token1));
        token0.approve(address(freshAMM), 500 ether);
        token1.approve(address(freshAMM), 50 ether);

        uint256 lp = freshAMM.addLiquidity(500 ether, 50 ether);

        uint256 expectedLP = AMMLibrary.sqrt(500 ether * 50 ether);
        assertEq(lp, expectedLP);
        assertEq(freshAMM.balanceOf(user), expectedLP);
        vm.stopPrank();
    }

    function testcheckReserves() public {
        (uint256 reserve0, uint256 reserve1) = amm.getReserves();
        assertEq(reserve0, 500 ether);
        assertEq(reserve1, 50 ether);
    }

     function testAddLiquidityRevertsOnZeroAmount() public {
        vm.startPrank(user);
        token0.approve(address(amm), 100 ether);
        token1.approve(address(amm), 10 ether);
        vm.expectRevert("Amounts must be greater than zero");
        amm.addLiquidity(0, 10 ether);
        vm.stopPrank();
    }
    function testTwoSubsequentAddLiquidityandLPCheck() public{
     uint256 lpBefore = amm.totalSupply();
     vm.startPrank(userB);
     token0.approve(address(amm), 100 ether);
     token1.approve(address(amm), 10 ether);
     uint256 lpNew= amm.addLiquidity(100 ether , 10 ether);
     uint256 lpAfter = amm.totalSupply();
     assertEq(lpAfter, lpBefore + lpNew);
     assertEq(amm.balanceOf(userB), lpNew);
     assertEq(amm.reserve0(), 600 ether);
     vm.stopPrank();
    }
    function testAddLiquidityRevertsWithoutApproval() public {
        vm.startPrank(userB);
        vm.expectRevert();
        amm.addLiquidity(100 ether, 10 ether);
        vm.stopPrank();

    }
    function swapToken0ForToken1() public{
        uint256 amountIn = 100 ether;
        uint256 expectedOut = AMMLibrary.getAmountOut(amountIn, 500 ether, 50 ether);

        vm.startPrank(user);
        token0.approve(address(amm),amountIn);
        uint256 amountOut = amm.swap(amountIn, address(token0));
        vm.stopPrank();
        assertEq(amountOut, expectedOut);
        assertEq(token0.balanceOf(user), 10000 ether - 500 ether - amountIn);
        assertEq(token1.balanceOf(user), 10000 ether - 50 ether + amountOut);
        assertEq(amm.reserve0(), 600 ether);
        assertEq(amm.reserve1(), 50 ether - amountOut);
    }

    function swapToken1ForToken0() public{
        uint256 amountIn = 10 ether;
        uint256 expectedOut= AMMLibrary.getAmountOut(amountIn, 50 ether, 500 ether);
        vm.startPrank(user);
        token1.approve(address(amm), amountIn);
        uint256 amountOut = amm.swap(amountIn, address(token1));
        vm.stopPrank();
        assertEq(amountOut, expectedOut);
        assertEq(token1.balanceOf(user), 10000 ether - 50 ether - amountIn);
        assertEq(token0.balanceOf(user), 10000 ether - 500 ether + amountOut);
        assertEq(amm.reserve1(), 50 ether);
        assertEq(amm.reserve0(), 500 ether - amountOut);
    }


        function testSwapRevertsOnInvalidToken() public {

        MockERC20 randomToken = new MockERC20("X", "X");
        vm.startPrank(user);
        vm.expectRevert("Invalid token");
        amm.swap(100 ether, address(randomToken));
        vm.stopPrank();

    }

    function testSwapRevertsOnZeroAmount() public {
      vm.startPrank(user);
        vm.expectRevert("Amount must be greater than zero");
        amm.swap(0, address(token0));
        vm.stopPrank();

    }

    function testSwapRevertsWithoutApproval() public {
        vm.startPrank(userB);
        vm.expectRevert();
        amm.swap(100 ether, address(token0));
        vm.stopPrank();
    }
    function testRemoveLiquidity() public{
        uint256 lpAmount= amm.balanceOf(user);
        uint256 totalLP = amm.totalSupply();

        uint256 expectedAmount0= (lpAmount * amm.reserve0()) / totalLP;
        uint256 expectedAmount1= (lpAmount*amm.reserve1()) / totalLP;
        vm.startPrank(user);
        (uint256 amount0, uint256 amount1)= amm.removeLiquidity(lpAmount);
        vm.stopPrank();
        assertEq(amount0, expectedAmount0);
        assertEq(amount1, expectedAmount1);
    }
    function testRemoveLiquidityBurnsLPTokens() public{
        uint256 lpBalance= amm.balanceOf(user);
        vm.startPrank(user);
        amm.removeLiquidity(lpBalance);
        vm.stopPrank();
         
        assertEq(amm.balanceOf(user),0);
        assertEq(amm.totalSupply(),0);
    }

    function testRemoveLiquidityUpdatesReserves() public {
        uint256 lpBalance = amm.balanceOf(user);

        vm.startPrank(user);
        amm.removeLiquidity(lpBalance);
        vm.stopPrank();

        assertEq(amm.reserve0(), 0);
        assertEq(amm.reserve1(), 0);
        }

    function testRemoveLiquidityRevertsOnZero() public {
        vm.startPrank(user);
        vm.expectRevert("Amount must be greater than zero");
        amm.removeLiquidity(0);
        vm.stopPrank();
    }

    function testRemoveLiquidityRevertsOnInsufficientBalance() public {
        vm.startPrank(userB);
        vm.expectRevert("Insufficient LP balance");
        amm.removeLiquidity(100 ether);
        vm.stopPrank();
    }

    function testSpotPriceReflectsReserves() public{
        uint256 spotPrice = AMMLibrary.getSpotPrice(
            amm.reserve0(), amm.reserve1()
        );
        uint256 expectedPrice = (50 ether * 1e18)/ 500 ether;
        assertEq(spotPrice, expectedPrice);

    }
    function testSpotPriceAfterSwap() public{
        uint256 spotPricebefore = AMMLibrary.getSpotPrice(amm.reserve0(), amm.reserve1());

        vm.startPrank(user);
         token0.approve(address(amm), 100 ether);
    amm.swap(100 ether, address(token0));
    vm.stopPrank();
    uint256 priceAfter = AMMLibrary.getSpotPrice(amm.reserve0(), amm.reserve1());
    assertLt(priceAfter, spotPricebefore);
     }
  
  function testTWAPManualCheckpoint() public {
    uint256 price1 = AMMLibrary.getSpotPrice(amm.reserve0(), amm.reserve1());
    uint256 time1  = block.timestamp;

    vm.warp(block.timestamp + 100);

    vm.startPrank(userB);
    token0.approve(address(amm), 200 ether);
    amm.swap(200 ether, address(token0));
    vm.stopPrank();

    uint256 price2 = AMMLibrary.getSpotPrice(amm.reserve0(), amm.reserve1());
    uint256 time2  = block.timestamp;

    vm.warp(block.timestamp + 100);

    uint256 twap = (price1 * 100 + price2 * 100) / (time2 - time1 + 100);

    assertGt(twap, 0);
    assertLt(twap, price1);
    assertGe(twap, price2);
}

function testTWAPHarderToManipulateThanSpot() public {
    uint256 twapBefore = AMMLibrary.getSpotPrice(
        amm.reserve0(),
        amm.reserve1()
    );

    vm.startPrank(attacker);
    token0.approve(address(amm), 900 ether);
    amm.swap(900 ether, address(token0));
    vm.stopPrank();

    uint256 spotAfter = AMMLibrary.getSpotPrice(
        amm.reserve0(),
        amm.reserve1()
    );

    // spot price collapsed by more than half
    assertLt(spotAfter, twapBefore / 2);

    // TWAP over 1 hour — attacker held fake price for only 1 second
    uint256 oneHour    = 3600;
    uint256 twapApprox = (twapBefore * (oneHour - 1) + spotAfter * 1) / oneHour;
    assertGt(twapApprox, spotAfter * 3);

    // also assert TWAP stayed close to original price
    // twapApprox should be within 1% of twapBefore
    assertGt(twapApprox, (twapBefore * 99) / 100);
}
 function testRouterSwapExactTokens() public {
        uint256 amountIn    = 100 ether;
        uint256 expectedOut = AMMLibrary.getAmountOut(amountIn, 500 ether, 50 ether);

        vm.startPrank(user);
        token0.approve(address(router), amountIn);
        uint256 amountOut = router.swapExactTokensForTokens(
            amountIn,
            expectedOut,        // minAmountOut = exact expected (no slippage tolerance)
            address(token0),
            address(amm)
        );
        vm.stopPrank();

        assertEq(amountOut, expectedOut);
    }
      function testRouterRevertsOnSlippage() public {
        uint256 amountIn = 100 ether;

        vm.startPrank(user);
        token0.approve(address(router), amountIn);
        vm.expectRevert("INSUFFICIENT_OUTPUT_AMOUNT");
        router.swapExactTokensForTokens(
            amountIn,
            9990 ether,          // minAmountOut way too high — must revert
            address(token0),
            address(amm)
        );
        vm.stopPrank();
    }
        function testKNeverDecreasesAfterSwap() public {
        uint256 kBefore = amm.reserve0() * amm.reserve1();

        vm.startPrank(userB);
        token0.approve(address(amm), 100 ether);
        amm.swap(100 ether, address(token0));
        vm.stopPrank();

        uint256 kAfter = amm.reserve0() * amm.reserve1();

        // k must never decrease — fees make it grow slightly
        assertGe(kAfter, kBefore);

    }  

    function testKNeverDecreasesAfterMultipleSwaps() public {
        uint256 kBefore = amm.reserve0() * amm.reserve1();

        vm.startPrank(userB);
        token0.approve(address(amm), 300 ether);
        token1.approve(address(amm), 30 ether);

        amm.swap(100 ether, address(token0));
        amm.swap(50 ether,  address(token0));
        amm.swap(10 ether,  address(token1));
        vm.stopPrank();

        uint256 kAfter = amm.reserve0() * amm.reserve1();
        assertGe(kAfter, kBefore);
    }
        function testReservesMatchActualBalances() public {
        vm.startPrank(userB);
        token0.approve(address(amm), 100 ether);
        amm.swap(100 ether, address(token0));
        vm.stopPrank();

        // reserves must always match real token balances
        assertEq(amm.reserve0(), token0.balanceOf(address(amm)));
        assertEq(amm.reserve1(), token1.balanceOf(address(amm)));
    }

    function testLPSharesAddUpTo100Percent() public {
        vm.startPrank(userB);
        token0.approve(address(amm), 250 ether);
        token1.approve(address(amm), 25 ether);
        amm.addLiquidity(250 ether, 25 ether);
        vm.stopPrank();

        uint256 totalLP  = amm.totalSupply();
        uint256 userShare = amm.balanceOf(user);
        uint256 userBShare = amm.balanceOf(userB);

        // all LP tokens must be accounted for
        assertEq(userShare + userBShare, totalLP);
    }

    function testNoTokensLostDuringSwap() public {
        uint256 totalToken0Before = token0.balanceOf(user) + token0.balanceOf(address(amm));
        uint256 totalToken1Before = token1.balanceOf(user) + token1.balanceOf(address(amm));

        vm.startPrank(user);
        token0.approve(address(amm), 100 ether);
        amm.swap(100 ether, address(token0));
        vm.stopPrank();

        uint256 totalToken0After = token0.balanceOf(user) + token0.balanceOf(address(amm));
        uint256 totalToken1After = token1.balanceOf(user) + token1.balanceOf(address(amm));

        // total supply of each token across all addresses never changes
        assertEq(totalToken0Before, totalToken0After);
        assertEq(totalToken1Before, totalToken1After);
    }
    }