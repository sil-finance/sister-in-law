// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;


import "../interfaces/IStakeGatling.sol";
import "../interfaces/IPriceSafeChecker.sol";
import "../uniswapv2/interfaces/IUniswapV2Pair.sol";

// Storage layer implementation of MatchPairStableV2
contract MatchPairStorageStableV2 {
    
    uint256 public constant PROXY_INDEX = 4;
    IUniswapV2Pair public lpToken;
    IStakeGatling public stakeGatling;
    IPriceSafeChecker public priceChecker;
    //migrate via factory
    // IUniswapV2Factory public factoryAddress;

    struct UserInfo{
        address user;
        //actual fund point
        uint256 tokenPoint;
        // uint256 lpRate;
        uint256 totalSupply;
        uint256 tokenReserve;
    }
    
    uint256 public pendingToken0;
    uint256 public pendingToken1;
    uint256 public totalTokenPoint0;
    uint256 public totalTokenPoint1;

    // in UniswapV2.burn() call ,small LP cause Exception('UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED')
    uint256 public sentinelAmount = 500;
    // filter too small asset, saving gas
    uint256 public minMintToken0;
    uint256 public minMintToken1;

    mapping(address => UserInfo[]) userInfo0;
    mapping(address => UserInfo[]) userInfo1;

    event Stake(bool _index0, address _user, uint256 _amount);
}