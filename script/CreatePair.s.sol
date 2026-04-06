// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {AMMFactory} from "../src/AMMFactory.sol";

contract CreatePair is Script {
    function run() external {
        vm.startBroadcast();

        MockERC20 token0 = new MockERC20("Token0", "TK0");
        MockERC20 token1 = new MockERC20("Token1", "TK1");

        AMMFactory factory = new AMMFactory();
        factory.createPair(address(token0), address(token1));

        vm.stopBroadcast();
    }
}