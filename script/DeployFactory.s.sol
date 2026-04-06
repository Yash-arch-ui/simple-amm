// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {AMMFactory} from "../src/AMMFactory.sol";

contract DeployFactory is Script {
    function run() external {
        vm.startBroadcast();

        AMMFactory factory = new AMMFactory();

        vm.stopBroadcast();
    }
}