// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./utils/QueueStableStakesFuns.sol";
import "./MatchPairStorageStable.sol";
import "./MatchPairDelegator.sol";
contract MatchPairStable is MatchPairStorageStable, MatchPairDelegator {
    using QueueStableStakesFuns for QueueStableStakes;

    constructor(address _lpToken) public {
        lpToken =  IUniswapV2Pair(_lpToken);
        createQueue(true, 10e7);
        createQueue(false, 10e7);
    }
     /**  From Library  */
    function createQueue(bool _isFirst, uint256 _size) private {
        QueuePoolInfo storage self = _isFirst? queueStake0 : queueStake1;
        self.priorityQueue.create(_size);
        self.pendingQueue.create(_size);
    }

    function token(uint256 _index) public view override returns (address) {
        return _index == 0 ? lpToken.token0() : lpToken.token1();
    }

    function setPriceSafeChecker(address _priceChecker) public onlyOwner() {
        priceChecker = IPriceSafeChecker(_priceChecker);
    }
    
    function setStakeGatling(address _gatlinAddress) public onlyOwner() {
        stakeGatling = IStakeGatling(_gatlinAddress);
    }

    function setMintLimit(uint256 _minMintToken0, uint256 _minMintToken1) public onlyOwner() {
        minMintToken0 = _minMintToken0;
        minMintToken1 = _minMintToken1;
    }

    function implementation() public view override returns (address) {
        return IProxyRegistry(masterCaller()).getProxy(PROXY_INDEX);
    }
}