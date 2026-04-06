// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";
import {AMMRouter} from "../src/AMMRouter.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        MockERC20 token0 = new MockERC20("Token0", "TK0");
        MockERC20 token1 = new MockERC20("Token1", "TK1");

        SimpleAMM amm = new SimpleAMM(address(token0), address(token1));

        AMMRouter router = new AMMRouter();

        vm.stopBroadcast();
    }
}