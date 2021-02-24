// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./uniswapv2/interfaces/IUniswapV2Pair.sol";
import './uniswapv2/libraries/UniswapV2Library.sol';
import './uniswapv2/libraries/TransferHelper.sol';

import "./utils/QueueStakesFuns.sol";
import "./utils/MasterCaller.sol";
import "./interfaces/IStakeGatling.sol";
import "./interfaces/IMatchPair.sol";
import "./interfaces/IPriceSafeChecker.sol";
import "./MatchPairStorage.sol";



contract MatchPairDelegate is MatchPairStorage, IMatchPair, Ownable, MasterCaller{
    using SafeERC20 for IERC20;
    using QueueStakesFuns for QueueStakes;
    using SafeMath for uint256; 

    constructor() public {
        // lpToken =  IUniswapV2Pair(_lpToken);
        // createQueue(true, 10e7);
        // createQueue(false, 10e7);
    }

    function stake(uint256 _index, address _user,uint256 _amount) public override {
        
        toQueue(_index == 0, _user, _amount);
        updatePool();
    }
    
    function updatePool() private {
        (uint256 pendingA, uint256 pendingB) = ( queueStake0.totalPending, queueStake1.totalPending);

        if( pendingA !=0 && pendingB !=0 ) {
            
            (uint amountA, uint amountB) = getPairAmount( lpToken.token0(), lpToken.token1(), pendingA, pendingB ); 

            // if(IERC20(lpToken.token0()).balanceOf(address(this)) >= amountA) {
                TransferHelper.safeTransfer(lpToken.token0(), address(lpToken), amountA);
            // }
            // if(IERC20(lpToken.token1()).balanceOf(address(this)) >= amountB) {
                TransferHelper.safeTransfer(lpToken.token1(), address(lpToken), amountB);
            // }
            //mint LP
            uint liquidity = lpToken.mint(stakeGatling.lpStakeDst());
            //send Token to UniPair
            stakeGatling.stake(liquidity); // update Percent
            uint256 presentRate = stakeGatling.presentRate();




            pending2LP(true, amountA, liquidity, presentRate);//
            pending2LP(false,amountB, liquidity, presentRate);
            
        }
    }
    function getPairAmount(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired  ) private returns ( uint amountA, uint amountB) {
            
        (uint reserveA, uint reserveB,) = lpToken.getReserves();
        if(address(priceChecker) != address(0) ) {
            priceChecker.checkPrice(reserveA, reserveB);
        }

        uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
        if (amountBOptimal <= amountBDesired) {
            (amountA, amountB) = (amountADesired, amountBOptimal);
        } else {
            uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
            assert(amountAOptimal <= amountADesired);
            (amountA, amountB) = (amountAOptimal, amountBDesired);
        }
    }
    function untakeToken(uint256 _index, address _user,uint256 _amount) 
        public
        override
        returns (uint256 _tokenAmount) 
    {
        bool index0 = _index == 0;
        address tokenCurrent = index0 ? lpToken.token0() : lpToken.token1();
        
        _tokenAmount = untakePending(index0, _user, _amount);

        if(_tokenAmount < _amount) {
            uint256 amountRequerViaLp =  _amount.sub(_tokenAmount);
            //untake LP
            //calculator LP via _amount
            uint256 requirLp = amountRequerViaLp.mul(lpToken.totalSupply()).div(IERC20(tokenCurrent).balanceOf(address(lpToken)));

            if(requirLp > 0) { 
                
                uint256 burnedTokenAmount = untakeLP(_index, _user, requirLp);

        //         // send to user
                _tokenAmount = _tokenAmount.add(burnedTokenAmount);

            }
        }
        // transfer to Master
        TransferHelper.safeTransfer(tokenCurrent, masterCaller(), _tokenAmount);
    }

    function untakeLP(uint256 _index, address _user,uint256 _amount) private returns (uint256) {
        // update profitRate
        stakeGatling.withdraw(0);
        uint256 presentRate = stakeGatling.presentRate();
        bool index0 = _index == 0;
        //untake Specifical User LP. reqire user.lpAmount >= _amount;
        uint256 _untakeLP = lp2PriorityQueueSpecifical(index0, _user, _amount , presentRate);
        if(_untakeLP < 100 ){ //todo _untakeLP == 3
            return 0;
        }
        // (uint amount0, uint amount1) = stakeGatling.burn(address(this), _untakeLP);
        // (uint amountC , uint amountOther) = index0? (amount0, amount1) : (amount1, amount0);

        (uint amountC, uint amountOther) = stakeGatling.burn(address(this), _untakeLP);
        if(!index0) {
             (amountC , amountOther) = (amountOther, amountC);
        }
      
        // //send Token to Specifical user
        address tokenCurrent = index0 ? lpToken.token0() : lpToken.token1();

        
        // // // Partner`s LP to Pending
        uint tokenPreShare = amountOther.mul(1e36).div(_untakeLP);


        
        //move Partner`s LP to priorityQueue
        lp2PriorityQueue(!index0, _untakeLP, tokenPreShare, presentRate);
        // rebuild pair
        updatePool();
        return amountC;
    }
    
    function token(uint256 _index) public view override returns (address) {
        return _index == 0 ? lpToken.token0() : lpToken.token1();
    }

    //add to quequeEnd
    function toQueue(bool _isFirst, address _user,  uint256 _amount) private {
        QueuePoolInfo storage self =  getQueuePoolInfo(_isFirst); // _isFirst? queueStake0 : queueStake1;

        uint256 pIndex =  self.pendingQueue.append(UserStake( _user, _amount, 0));
        self.totalPending = self.totalPending.add(_amount);
        self.userPending[_user].push(pIndex);
        emit Stake(_isFirst, _user, _amount);

    }

    function getQueuePoolInfo(bool _isIndex0) private returns( QueuePoolInfo storage poolInfo ) {
        return _isIndex0 ? queueStake0 : queueStake1;
    }
    // untake from pendingQueue && priorityQueue
    function untakePending(bool _index0, address _user,  uint256 _amount) private returns (uint256 untakeAmount) {
        QueuePoolInfo storage self = _index0? queueStake0 : queueStake1;
        
        uint256[] storage pQueueIndex = self.userPending[_user];

        while(pQueueIndex.length>0) {
            uint256 pIndex = pQueueIndex[pQueueIndex.length.sub(1)];
            UserStake storage userStake = self.pendingQueue.indexOf(pIndex);
            uint256 amount = userStake.amount;
            if(untakeAmount.add(amount)>= _amount) {
                userStake.amount = untakeAmount.add(amount).sub(_amount);
                untakeAmount = _amount;    
                break;
            }else{
                untakeAmount = untakeAmount.add(amount);
                userStake.amount = 0;
                pQueueIndex.pop();
            }
        }
        if (untakeAmount < _amount) {
            uint256 untakeProority = untakePriority(_index0, _user, _amount.sub(untakeAmount));
            untakeAmount = untakeAmount.add(untakeProority);
        }

        self.totalPending = self.totalPending.sub(untakeAmount);
    }

    function untakePriority(bool _index0, address _user,  uint256 _amount) private returns(uint256 _untakeAmount) {
        QueuePoolInfo storage self = _index0? queueStake0 : queueStake1;
        uint256[] storage priorityIndex = self.userPriority[_user];
        uint256 untakeAmount;

        while( priorityIndex.length > 0 ) {
            uint256 pIndex = priorityIndex[priorityIndex.length.sub(1)];
            UserStake storage userStake = self.priorityQueue.indexOf(pIndex);
            uint256 amount = userStake.amount;
            //self assets only allows

            if(userStake.user != _user ) {
                break;
            }
            if(untakeAmount.add(amount)>= _amount) {
                userStake.amount = untakeAmount.add(amount).sub(_amount);
                return _amount;
            }else{
                untakeAmount = untakeAmount.add(amount);
                userStake.amount = 0;
                priorityIndex.pop();
            }
        }
        return untakeAmount;
    }

    function pending2LP(bool _index0, uint256 _amount, uint256 _liquidity, uint256 _presentRate) private {
        // lpRate
        uint256 lpPreShare =  _liquidity.mul(1e36).div(_amount);


        uint leftAmount = moveQueue2LP(_index0, true, _amount, lpPreShare, _presentRate);

        if(leftAmount>0) {
            moveQueue2LP(_index0, false, leftAmount, lpPreShare, _presentRate);
        }
        //update totalPending
        QueuePoolInfo storage self = _index0? queueStake0 : queueStake1;
        self.totalPending = self.totalPending.sub(_amount);
    }
    
    // LP to Priority
    function lp2PriorityQueueSpecifical(bool _index0, address _user, uint256 _amount, uint256 _presentRate) private returns(uint256 untakeAmount) {
        QueuePoolInfo storage self = _index0? queueStake0 : queueStake1;
        uint256[] storage lpIndex = self.userLP[_user];
        

        while( lpIndex.length > 0 ) {
            uint256 pIndex = lpIndex[lpIndex.length.sub(1)];
            UserStake storage userStake = self.lpQueue[pIndex]; 
            if(userStake.user != _user) {
                break;
            }


            // inflate profit
            uint256 amount = userStake.amount.mul(_presentRate).div(userStake.perRate);

            if(untakeAmount.add(amount)>= _amount) {
                userStake.amount = protectAmount(untakeAmount.add(amount).sub(_amount));
                untakeAmount = _amount;
                if(userStake.amount == 0){
                    lpIndex.pop();
                }else {
                    userStake.perRate = _presentRate; //updateRate
                }

                break;
            }else{
                untakeAmount = untakeAmount.add(amount);
                userStake.amount = 0; // if userStatel is not tail, cannot pop
                lpIndex.pop();
            }

        }
    }

     // LP to Priority
    function lp2PriorityQueue(bool _index0, uint256 _amount, uint _preShare, uint256 _presentRate) private {
        
        UserStake[] storage queueStakes =  _index0? queueStake0.lpQueue : queueStake1.lpQueue;
        mapping(address => uint256[]) storage userLp =  _index0? queueStake0.userLP : queueStake1.userLP;
        uint untakeAmount = _amount;

        while(queueStakes.length>0) {
            //latest one
            UserStake storage userStake = queueStakes[queueStakes.length.sub(1)];
            // inflate profit
            uint256 amount = userStake.amount.mul(_presentRate).div(userStake.perRate); // profit


            address _user = userStake.user;
            if(amount ==0) {
                queueStakes.pop();
                userLp[_user].pop();
                continue;
            }
            if(untakeAmount <= amount) {
                appendPriority(_index0, _user, untakeAmount, _preShare);
                if(untakeAmount == amount ) {
                    userStake.amount = 0;
                    queueStakes.pop();
                    userLp[_user].pop();
                }else {
                    userStake.amount = protectAmount(amount.sub(untakeAmount));
                    userStake.perRate = _presentRate;
                }
                untakeAmount = 0; 
                break;
            }else {
                appendPriority(_index0, _user, amount, _preShare);
                untakeAmount = untakeAmount.sub(amount);
                userStake.amount = 0; 
                queueStakes.pop();
                userLp[_user].pop();
            }
        }
    }
    /**
     * @dev _amount , totoal amount to LP 
     * return left Amount to LP , pick from pendingQueue
     */
    function moveQueue2LP(bool _index0, bool isPriority, uint256 _amount , uint256 lpPreShare, uint256 _presentRate) private returns(uint256 untakeAmount) {
        QueuePoolInfo storage self = _index0? queueStake0 : queueStake1;
        QueueStakes storage queueStakes =  isPriority ? self.priorityQueue : self.pendingQueue;
        untakeAmount = _amount;
        while(queueStakes.used>0) { //used == length
            UserStake storage userStake = queueStakes.first();
            uint256 amount = userStake.amount;
            if(amount ==0) { // bean removed todo? is necessary 
                queueStakes.remove();
                continue;
            }
            if(untakeAmount <= amount) {
                if(untakeAmount == amount ) {
                    userStake.amount = 0;
                    queueStakes.remove();
                }else{
                    userStake.amount = amount.sub(untakeAmount);
                }
                appendLP(_index0, userStake.user, untakeAmount,  lpPreShare, _presentRate);
                untakeAmount = 0; 
                break;
            }else {
                untakeAmount = untakeAmount.sub(amount);
                userStake.amount = 0;
                queueStakes.remove();
                appendLP(_index0, userStake.user, amount,  lpPreShare, _presentRate);
            }
        }
    }
    /**
     * move pending to LP
     */
    function appendLP(bool _index0,address _user, uint _amount, uint _lpRate, uint256 _presentRate) private {


        //Small amounts cause calculation failure
        if(_amount > safeProtect) {
            QueuePoolInfo storage self = _index0? queueStake0 : queueStake1;
            self.userLP[_user].push(self.lpQueue.length);
            uint256 lpAmount = _amount.mul(_lpRate).div(1e36);
            self.lpQueue.push(UserStake( _user, lpAmount, _presentRate));

        }
    }

    function protectAmount(uint256 _amount) private returns(uint256) {
        return _amount > safeProtect? _amount : 0;
    }
    /**
     * move pending to Priority
     */
    function appendPriority(bool _index0, address _user, uint _amount, uint _lpRate) private {

        QueuePoolInfo storage self = _index0? queueStake0 : queueStake1;   
        uint256 pid = self.priorityQueue.append(UserStake( _user, _amount.mul(_lpRate).div(1e36), 0));
        self.userPriority[_user].push(pid);

        self.totalPending = self.totalPending.add( _amount.mul(_lpRate).div(1e36));
    }

    function lPAmount(uint256 _index, address _user) public view returns (uint256) {
        //gatlin profit rate
        uint256 presentRate = stakeGatling.presentRate();

        uint256 totalLPAmount;
        QueuePoolInfo memory self = _index == 0? queueStake0 : queueStake1;
        UserStake[] memory lpQueue = self.lpQueue;
        uint256[] memory lps =  _index == 0? queueStake0.userLP[_user] : queueStake1.userLP[_user];
        //lpQueue partion
        for (uint i=0; i< lps.length; i++) {
            uint256 amount = lpQueue[lps[i]].amount.mul(presentRate).div(lpQueue[lps[i]].perRate);
            totalLPAmount = totalLPAmount.add(amount);
        }
        return totalLPAmount;
    }

    function tokenAmount(uint256 _index, address _user) public view returns (uint256) {
        //gatlin profit rate
        uint256 totalLPAmount;
        QueuePoolInfo storage self = _index == 0? queueStake0 : queueStake1;

        uint256[] storage _userPriority = self.userPriority[_user];
        if( _userPriority.length > 0 ) {
            QueueStakes storage  _priorityQueue = self.priorityQueue;

            for (uint i=0; i< _userPriority.length; i++) {
                
                uint256 amount = _priorityQueue.indexOfView( _userPriority[i] ).amount;
                totalLPAmount = totalLPAmount.add(amount);
            }
        }

        uint256[] storage _userPending = self.userPending[_user];
        if( _userPending.length > 0 ) {
            QueueStakes storage  _pendingQueue = self.pendingQueue;

            for (uint i=0; i< _userPending.length; i++) {
                
                uint256 amount = _pendingQueue.indexOfView( _userPending[i]).amount;
                totalLPAmount = totalLPAmount.add(amount);
            }
        }
        return totalLPAmount;
    }

    function queueTokenAmount(uint256 _index) public view override  returns (uint256) {
        QueuePoolInfo storage self = _index == 0? queueStake0 : queueStake1;
        return self.totalPending;
    }

    function lp2TokenAmount(uint256 _liquidity) public view  returns (uint256 amount0, uint256 amount1) {

        uint256 _totalSupply = lpToken.totalSupply();
        (address _token0, address _token1) = (lpToken.token0(), lpToken.token1());

        uint balance0 = IERC20(_token0).balanceOf(address(lpToken));
        uint balance1 = IERC20(_token1).balanceOf(address(lpToken));

        amount0 = _liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = _liquidity.mul(balance1) / _totalSupply;

    }

    function maxAcceptAmount(uint256 _index, uint256 _molecular, uint256 _denominator, uint256 _inputAmount) public view override returns (uint256) {
        
        QueuePoolInfo storage info =  _index == 0? queueStake0: queueStake1;
        (uint256 amount0, uint256 amount1) = stakeGatling.totalToken();

        uint256 pendingTokenAmount = info.totalPending;
        uint256 lpTokenAmount =  _index == 0 ? amount0 : amount1;

        require(lpTokenAmount.mul(_molecular).div(_denominator) > pendingTokenAmount, "Amount in pool less than PendingAmount");
        uint256 maxAmount = lpTokenAmount.mul(_molecular).div(_denominator).sub(pendingTokenAmount);
        
        return _inputAmount > maxAmount ? maxAmount : _inputAmount ; 
    }

    // todo to be remove

    function userLPIndex(uint256 _side, address _account) external view returns(UserStake[] memory ) {

        uint256[] storage _userLp =  _side == 0? queueStake0.userLP[_account] : queueStake1.userLP[_account];
        UserStake[] storage _lpQueue =  _side == 0? queueStake0.lpQueue : queueStake1.lpQueue;

        UserStake[] memory stakes = new UserStake[](_userLp.length); 

        for (uint i=0; i < _userLp.length; i++) { 
            stakes[i] = _lpQueue[_userLp[i]];
        }
        return stakes;
    }
}
