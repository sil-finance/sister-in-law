// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./uniswapv2/interfaces/IUniswapV2Pair.sol";

import "./interfaces/IStakeGatling.sol";
import "./interfaces/IPriceSafeChecker.sol";
import "./utils/QueueStableStakesFuns.sol";

contract MatchPairStorageStable {
   uint256 public constant PROXY_INDEX = 1;
    // round index of pair order
    uint256 public pairRound;
    uint256 public minMintToken0;
    uint256 public minMintToken1;
    uint256 safeProtect = 50;

    struct QueuePoolInfo {
        //LP Token : LIFO
        UserStableStake[] lpQueue;
        //from LP to priorityQueue :FIFO
        QueueStableStakes priorityQueue;
        //Single Token  : FIFO
        QueueStableStakes pendingQueue;
        //Queue Total
        uint256 totalPending;
        //index of User index
        mapping(address => uint256[]) userLP;
        mapping(address => uint256[]) userPriority;
        mapping(address => uint256[]) userPending;
    }

    struct UserAmount {
        address user;
        uint256 amount;
    }

    struct RequestWrapper {
        uint256 index;
        address user;
        uint256 amount;
        uint256 rate;
        uint256 rate2;
    }
    
    //queue wrap
    QueuePoolInfo queueStake0;
    QueuePoolInfo queueStake1;
    //LP token Address
    IUniswapV2Pair public lpToken;
    IStakeGatling stakeGatling;
    IPriceSafeChecker priceChecker;
    // LP index array each round
    // index0/1 => round => lpIndex[]
    mapping(uint256 => mapping(uint256 => uint256[])) roundLpIndex;

    event Stake(bool _index0, address _user, uint256 _amount);
    // int256 constant INT256_MAX = int256(~(uint256(1) << 255));
}
