//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;
import "./Pair.sol";
contract AMMFactory{
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);


    function createPair(address tokenA, address tokenB) external returns(address pair){
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        require(tokenA != address(0), "ZERO_ADDRESSES");

        (address token0, address token1)= tokenA<tokenB ? (tokenA,tokenB): (tokenB,tokenA);

        require(getPair[token0][token1] == address(0), "PAIR_EXISTS");
// CREATE 2 OPCODE//
        bytes memory bytecode = type(AMMPair).creationCode;
        bytes32 salt= keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0,add(bytecode,32), mload(bytecode),salt)

        } 
        //
        AMMPair(pair).initialize(token0, token1);
        getPair[token0][token1]= pair;
        getPair[token1][token0]= pair; // convenice reverse lookup
        allPairs.push(pair);

        emit PairCreated(token0,token1,pair,allPairs.length);

    }
    function allPairsLength() external view returns(uint){
        return allPairs.length;
    }
}

