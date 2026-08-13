//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";
import {AMMLibrary} from "../src/AMMLibrary.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {FlashLoanReceiver} from "../src/FlashLoanReceiver.sol";
import {IUniswapV2Callee} from "../src/IUniswapV2Callee.sol";

contract ScriptedBorrower is IUniswapV2Callee {
    address public immutable pair;
    address public immutable token0;
    address public immutable token1;

    constructor(address _pair, address _token0, address _token1) {
        pair = _pair;
        token0 = _token0;
        token1 = _token1;
    }

    function borrow(uint256 amount0Out, uint256 amount1Out, bytes calldata data) external {
        SimpleAMM(pair).swap(amount0Out, amount1Out, address(this), data);
    }

    function uniswapV2Call(address, uint256, uint256, bytes calldata data) external {
        require(msg.sender == pair, "NOT_PAIR");
        (uint256 repay0, uint256 repay1) = abi.decode(data, (uint256, uint256));
        if (repay0 > 0) IERC20(token0).transfer(pair, repay0);
        if (repay1 > 0) IERC20(token1).transfer(pair, repay1);
    }
}

contract FlashLoanTest is Test {
    MockERC20 token0;
    MockERC20 token1;
    SimpleAMM poolA;
    SimpleAMM poolB;
    FlashLoanReceiver receiver;
    ScriptedBorrower borrower;

    address user = makeAddr("user");
    address attacker = makeAddr("attacker");

    function setUp() public {
        token0 = new MockERC20("Token0", "TK0");
        token1 = new MockERC20("Token1", "TK1");
        poolA = new SimpleAMM(address(token0), address(token1));
        poolB = new SimpleAMM(address(token0), address(token1));

        token0.mint(user, 10000 ether);
        token1.mint(user, 10000 ether);

        vm.startPrank(user);
        token0.approve(address(poolA), 500 ether);
        token1.approve(address(poolA), 50 ether);
        poolA.addLiquidity(500 ether, 50 ether);
        vm.stopPrank();

        receiver = new FlashLoanReceiver(address(poolA));
        borrower = new ScriptedBorrower(address(poolA), address(token0), address(token1));
        token0.mint(address(borrower), 1000 ether);
        token1.mint(address(borrower), 1000 ether);
    }

    function _addLiquidityToB(uint256 amount0, uint256 amount1) internal {
        token0.mint(user, amount0);
        token1.mint(user, amount1);
        vm.startPrank(user);
        token0.approve(address(poolB), amount0);
        token1.approve(address(poolB), amount1);
        poolB.addLiquidity(amount0, amount1);
        vm.stopPrank();
    }

    function testFlashSwapRepaySameTokenWithFee() public {
        borrower.borrow(100 ether, 0, abi.encode(101 ether, uint256(0)));
        assertEq(poolA.reserve0(), 501 ether);
        assertEq(poolA.reserve1(), 50 ether);
    }

    function testFlashSwapRevertsIfNotRepaid() public {
        vm.expectRevert("Insufficient input amount");
        borrower.borrow(100 ether, 0, abi.encode(uint256(0), uint256(0)));
    }

    function testFlashSwapRevertsIfRepaidWithoutFee() public {
        vm.expectRevert("K_CHECK");
        borrower.borrow(100 ether, 0, abi.encode(100 ether, uint256(0)));
    }

    function testFlashSwapRevertsIfPartialFee() public {
        vm.expectRevert("K_CHECK");
        borrower.borrow(100 ether, 0, abi.encode(100.3 ether, uint256(0)));
    }

    function testFlashSwapRevertsOnZeroOutput() public {
        vm.expectRevert("Insufficient output amount");
        poolA.swap(0, 0, address(borrower), abi.encode(uint256(0), uint256(0)));
    }

    function testFlashSwapRevertsWhenBorrowingMoreThanLiquidity() public {
        vm.expectRevert("Insufficient liquidity");
        borrower.borrow(500 ether, 0, abi.encode(101 ether, uint256(0)));
    }

    function testFlashLoanArbitrageBorrowToken0() public {
        _addLiquidityToB(1000 ether, 150 ether);
        uint256 expectedOut1 = AMMLibrary.getAmountOut(100 ether, poolB.reserve0(), poolB.reserve1());
        uint256 expectedRepay = AMMLibrary.getAmountIn(100 ether, poolA.reserve1(), poolA.reserve0());

        receiver.flashBorrow(100 ether, 0, abi.encode(address(poolB), uint256(0)));

        assertEq(poolA.reserve0(), 400 ether);
        assertEq(poolA.reserve1(), 50 ether + expectedRepay);
        assertEq(poolB.reserve0(), 1000 ether + 100 ether);
        assertEq(poolB.reserve1(), 150 ether - expectedOut1);
        assertGt(receiver.profit(), 0);
        assertEq(receiver.profit(), expectedOut1 - expectedRepay);
    }

    function testFlashLoanArbitrageBorrowToken1() public {
        _addLiquidityToB(2000 ether, 100 ether);
        uint256 expectedOut0 = AMMLibrary.getAmountOut(10 ether, poolB.reserve1(), poolB.reserve0());
        uint256 expectedRepay = AMMLibrary.getAmountIn(10 ether, poolA.reserve0(), poolA.reserve1());

        receiver.flashBorrow(0, 10 ether, abi.encode(address(poolB), uint256(0)));

        assertEq(poolA.reserve0(), 500 ether + expectedRepay);
        assertEq(poolA.reserve1(), 40 ether);
        assertEq(poolB.reserve0(), 2000 ether - expectedOut0);
        assertEq(poolB.reserve1(), 110 ether);
        assertGt(receiver.profit(), 0);
        assertEq(receiver.profit(), expectedOut0 - expectedRepay);
    }

    function testFlashLoanArbitrageProfitWithdrawable() public {
        _addLiquidityToB(1000 ether, 150 ether);
        uint256 expectedOut1 = AMMLibrary.getAmountOut(100 ether, poolB.reserve0(), poolB.reserve1());
        uint256 expectedRepay = AMMLibrary.getAmountIn(100 ether, poolA.reserve1(), poolA.reserve0());

        receiver.flashBorrow(100 ether, 0, abi.encode(address(poolB), uint256(0)));
        receiver.withdraw(address(token1));

        assertEq(token1.balanceOf(address(this)), expectedOut1 - expectedRepay);
    }

    function testFlashLoanArbitrageRevertsIfUnprofitable() public {
        _addLiquidityToB(900 ether, 60 ether);
        vm.expectRevert("UNPROFITABLE");
        receiver.flashBorrow(100 ether, 0, abi.encode(address(poolB), uint256(0)));
    }

    function testFlashBorrowRevertsForNonOwner() public {
        vm.startPrank(attacker);
        vm.expectRevert("NOT_OWNER");
        receiver.flashBorrow(100 ether, 0, abi.encode(address(poolB), uint256(0)));
        vm.stopPrank();
    }

    function testUniswapV2CallRevertsForNonPair() public {
        vm.startPrank(attacker);
        vm.expectRevert("NOT_PAIR");
        receiver.uniswapV2Call(attacker, 0, 0, "");
        vm.stopPrank();
    }

    function testWithdrawRevertsForNonOwner() public {
        vm.startPrank(attacker);
        vm.expectRevert("NOT_OWNER");
        receiver.withdraw(address(token0));
        vm.stopPrank();
    }

    function testSwapEventEmitted() public {
        vm.expectEmit(true, true, true, true, address(poolA));
        emit SimpleAMM.Swap(address(borrower), 101 ether, 0, 100 ether, 0, address(borrower));
        borrower.borrow(100 ether, 0, abi.encode(101 ether, uint256(0)));
    }

    function testNoTokensStuckInPair() public {
        borrower.borrow(100 ether, 0, abi.encode(101 ether, uint256(0)));
        assertEq(token0.balanceOf(address(poolA)), poolA.reserve0());
        assertEq(token1.balanceOf(address(poolA)), poolA.reserve1());
    }
}
