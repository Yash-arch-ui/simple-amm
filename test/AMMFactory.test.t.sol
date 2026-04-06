//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;
import {AMMFactory} from "../src/AMMFactory.sol";
import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "../src/MockERC20.sol";
contract AMMFactoryTest is Test {
  MockERC20 token0;
  MockERC20 token1;
 AMMFactory factory;

function setUp() public{
    token0= new MockERC20("Token0", "TK0");
    token1= new MockERC20("Token1", "TK1");

    factory = new AMMFactory();
}

function testActuallyChecksPairCreationFlow() public {
  address pair1= factory.createPair(address(token0), address(token1));
  address pair2= factory.getPair(address(token0), address(token1));

  assertEq(pair1, pair2);

}

function testRevertsInCaseOfDuplicatePairs() public  {
    factory.createPair(address(token0), address(token1));
    vm.expectRevert();
    factory.createPair(address(token0), address(token1));
    }

function testTokenOrderSamePair() public {

    address pair1 = factory.createPair(address(token0), address(token1));
    address pair2 = factory.getPair(address(token1), address(token0));

    assertEq(pair1, pair2);
}

   function testZeroAddressProtection() public{
    vm.expectRevert();
    address pair1= factory.createPair(address(0), address(token1));

   }
}