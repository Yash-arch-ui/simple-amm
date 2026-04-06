//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;



contract AMMPair{
    address public token0;
    address public token1;
    address public factory;

    function initialize(address _token0, address _token1) external{
        require(factory == address (0), "ALREADY_INITIALIZED");
        factory= msg.sender;
        token0= _token0;
        token1=_token1;
    }
}