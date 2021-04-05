// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../uniswapv2/interfaces/IUniswapV2Pair.sol";
import '../uniswapv2/libraries/UniswapV2Library.sol';
import '../uniswapv2/libraries/TransferHelper.sol';

import "../utils/MasterCaller.sol";
import "../interfaces/IStakeGatling.sol";
import "../interfaces/IMatchPair.sol";
import "../interfaces/IPriceSafeChecker.sol";
import "../storage/MatchPairStorageStableV2.sol";

// Logic layer implementation of MatchPairStableV2
contract MatchPairStableDelegateV2 is MatchPairStorageStableV2,  IMatchPair, Ownable, MasterCaller{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    

    constructor(address _lpAddress) public {
        lpToken = IUniswapV2Pair(_lpAddress);
    }
    function setStakeGatling(address _gatlinAddress) public onlyOwner() {
        stakeGatling = IStakeGatling(_gatlinAddress);
    }

    /**
     * @notice Just logic layer
     */
    function stake(uint256 _index, address _user,uint256 _amount) public  override {

        // 1. updateLpAmount
        _updateLpProfit();
        (uint256 lpTokenAmount, uint256 lpTokenAmoun1) = stakeGatling.totalToken();

        if (_index == 1) {
            lpTokenAmount = lpTokenAmoun1;
        }
        (uint256 pendingAmount, uint256 totalPoint) = _getPendingAndPoint(_index);

        uint256 userPoint;
        {
            if(totalPoint == 0 || lpTokenAmount.add(pendingAmount) == 0) {
                userPoint = _amount;
            }else {
                userPoint = _amount.mul(totalPoint).div(lpTokenAmount.add(pendingAmount));
            }
        }
        _addPendingAmount(_index, _amount);
        _addUserStake(_index, _user, userPoint);
        updatePool();
    }

    

    function _getPendingAndPoint(uint256 _index) private returns (uint256 pendingAmount,uint256 totalPoint) {
        if(_index == 0) {
            return (pendingToken0, totalTokenPoint0);
        }else {
            return (pendingToken1, totalTokenPoint1);
        }
    }
    
    function updatePool() private {

        if( pendingToken0 > minMintToken0 && pendingToken1 > minMintToken1 ) {

            (uint amountA, uint amountB) = getPairAmount( pendingToken0, pendingToken1 ); 
            if( amountA > minMintToken0 && amountB > minMintToken1 ) {
                
                TransferHelper.safeTransfer(lpToken.token0(), address(lpToken), amountA);
                TransferHelper.safeTransfer(lpToken.token1(), address(lpToken), amountB);
                pendingToken0 = pendingToken0.sub(amountA);
                pendingToken1 = pendingToken1.sub(amountB);
                //mint LP
                uint liquidity = lpToken.mint(stakeGatling.lpStakeDst());
                //send Token to UniPair
                stakeGatling.stake(liquidity);
            }
        }
    }
    function getPairAmount(
        uint amountADesired,
        uint amountBDesired  ) private returns ( uint amountA, uint amountB) {

        (uint reserveA, uint reserveB,) = lpToken.getReserves();
        _checkPrice(reserveA, reserveB);

        uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
        if (amountBOptimal <= amountBDesired) {
            (amountA, amountB) = (amountADesired, amountBOptimal);
        } else {
            uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
            assert(amountAOptimal <= amountADesired);
            (amountA, amountB) = (amountAOptimal, amountBDesired);
        }
    }
    function untakeToken(uint256 _index, address _user, uint256 _amount) 
        public
        override
        returns (uint256 _withdrawAmount, uint256 _leftAmount) 
    {
        _updateLpProfit();
        (uint256 untakePoint, uint256 untakeOriginalAmount, uint256 leftPoint, uint256 leftLpAmount ) = untakePreCalc(_index == 0, _user, _amount);

        (uint256 pendingAmount, uint256 totalPoint) = _getPendingAndPoint(_index);

        {
            uint256 non_il_amount = _userAmountByPoint(untakePoint , totalPoint, pendingAmount );
            uint256 lp_amount = _userAmountByPoint(untakePoint , totalPoint, stakeGatling.totalLPAmount());

            //burn and cover impermanence loss
            (uint256 tokenCurrent, uint256 tokenPaired) = burnLpWithExpect(_index, lp_amount, untakeOriginalAmount.sub(non_il_amount));

            _withdrawAmount = non_il_amount.add(tokenCurrent);
            if(_index == 0 ) {
                pendingToken0 = pendingToken0.sub(non_il_amount);
                pendingToken1 = pendingToken1.add(tokenPaired);
            }else {
                pendingToken1 = pendingToken1.sub(non_il_amount);
                pendingToken0 = pendingToken0.add(tokenPaired);
            }
        }
        _subTotalPoint(_index, untakePoint);

        //
        //update Pending & totalPoint
        (pendingAmount, totalPoint) = _getPendingAndPoint(_index);

        _leftAmount = leftLpAmount.add(_userAmountByPoint(leftPoint, totalPoint, pendingAmount));

        // transfer to Master
        TransferHelper.safeTransfer( _index == 0 ? lpToken.token0() : lpToken.token1(), masterCaller(), _withdrawAmount);
    }

    function burnLpWithExpect(uint256 _index, uint256 _lpAmount, uint256 expectTokenByLP)
        private 
        returns (uint256 tokenCurrent, uint256 tokenPaired)
    {
        if(_lpAmount < sentinelAmount) {
            return (0,0);
        }
        (tokenCurrent, tokenPaired) = _burnLp(_index, _lpAmount);

        if (expectTokenByLP > tokenCurrent) { // Lose: sell paird Token for currentToken
            uint256 expectPaired = tokenCurrent.mul(tokenPaired).div(expectTokenByLP);

            uint256 sellPaired = tokenPaired.sub(expectPaired);
            uint256 amountOut = _execSwap((_index+1)%2 , sellPaired);          

            tokenCurrent = tokenCurrent.add(amountOut);
            tokenPaired = tokenPaired.sub(sellPaired);
        }

        if (expectTokenByLP < tokenCurrent) { //Win: Sell current Token for paired Token

            uint256 sellAmount = tokenCurrent.sub(expectTokenByLP);
            uint256 amountOut = _execSwap(_index, sellAmount);

            tokenCurrent = tokenCurrent.sub(sellAmount);
            tokenPaired = tokenPaired.add(amountOut);
        }
    }

    function _execSwap(uint256 indexIn, uint256 amountIn ) private returns(uint256 amountOunt) {

        if(amountIn > 0) {
            amountOunt = _getAmountVoutIndexed( indexIn,  amountIn);


            address sellToken = indexIn == 0? lpToken.token0() : lpToken.token1();
            TransferHelper.safeTransfer(sellToken, address(lpToken), amountIn);
            uint256 zero;
            (uint256 amount0Out, uint256 amount1Out ) = indexIn == 0 ? ( zero , amountOunt ) : (amountOunt, zero);
            lpToken.swap(amount0Out, amount1Out, address(this), new bytes(0));
        }
    }

     function _getAmountVoutIndexed(uint256 _inIndex, uint256 _amountIn ) private returns(uint256 amountOut) {
        (uint256 _reserveIn, uint256 _reserveOut, ) = lpToken.getReserves();
        if(_inIndex == 1) {
            (_reserveIn, _reserveOut) = (_reserveOut, _reserveIn);
        }
        amountOut = _getAmountOut(_amountIn, _reserveIn, _reserveOut);
    }


    function _getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {

        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    function _burnLp(uint256 _index, uint256 _lpAmount) private returns (uint256 tokenCurrent, uint256 tokenPaired) {
        //precheck before call this function
        // if(_lpAmount > sentinelAmount) {
        (tokenCurrent, tokenPaired) = stakeGatling.burn(address(this), _lpAmount);
        if(_index == 1) {
            (tokenCurrent, tokenPaired) = (tokenPaired, tokenCurrent );
        }
        // }
    }

    function untakePreCalc(bool _index0, address _user,  uint256 _expectAmount) 
        private 
        returns (uint256 untakePoint, uint256 untakeOriginalAmount, uint256 _leftPoint, uint256 _leftLpAmount) 
    { 
        UserInfo[] storage stakeQueue = _index0? userInfo0[_user] : userInfo1[_user];

        uint256 totaPending = _index0? pendingToken0 : pendingToken1;
        uint256 totalPoint = _index0? totalTokenPoint0 : totalTokenPoint1;
        uint256 totaLp = stakeGatling.totalLPAmount();

        while(stakeQueue.length>0) {
            //Pop from array end
            UserInfo storage user = stakeQueue[stakeQueue.length - 1];
            //userAmount = pendingShare + lpShare.lpRate
            uint256 _amount = _userAmountByPoint(user.tokenPoint, totalPoint, totaPending)
                            .add(_userAmountByPoint(user.tokenPoint, totalPoint, totaLp).mul(user.tokenReserve).div(user.totalSupply));


            if(_expectAmount < _amount) {
                uint256 _untakePointPart = _expectAmount.mul(user.tokenPoint).div(_amount);
                user.tokenPoint = user.tokenPoint.sub(_untakePointPart);

                untakePoint = untakePoint.add(_untakePointPart);
                untakeOriginalAmount = untakeOriginalAmount.add(_expectAmount);
                break;
            }else {
                _expectAmount = _expectAmount.sub(_amount);
                untakePoint = untakePoint.add(user.tokenPoint);
                untakeOriginalAmount = untakeOriginalAmount.add(_amount);
                stakeQueue.pop();
                if(_expectAmount == 0){
                    break;
                }
            }
        }

        //calculate left amount 
        if(stakeQueue.length > 0) {
            uint256 stakeLength = stakeQueue.length;
            for (uint i=0; i < stakeLength; i++) {
                UserInfo storage user = stakeQueue[i];
                _leftPoint = _leftPoint.add(user.tokenPoint);
                uint256 _lpAmount = _userAmountByPoint(user.tokenPoint, totalPoint, totaLp).mul(user.tokenReserve).div(user.totalSupply);


               _leftLpAmount = _leftLpAmount.add(_lpAmount);
            }
        }
    }

    /**
     * @notice price feeded by  Oracle
     */
    function _checkPrice(uint256 reserve0, uint256 reserve1) private {
        if(address(priceChecker) != address(0) ) {
            priceChecker.checkPrice(reserve0, reserve1);
        }
    }
    /**
     * @notice Compound interest calculation in Gatling layer
     */
    function _updateLpProfit() private {

        stakeGatling.withdraw(0);

    }

    function _subPendingAmount(uint256 _index, uint256 _amount) private {
        if(_index == 0) {
            pendingToken0 = pendingToken0.sub(_amount);
        }else {
            pendingToken1 = pendingToken1.sub(_amount);
        }
    }

    function _addPendingAmount(uint256 _index, uint256 _amount) private {
        if(_index == 0) {
            pendingToken0 = pendingToken0.add(_amount);
        }else {
            pendingToken1 = pendingToken1.add(_amount);
        }
    }

    function _subTotalPoint(uint256 _index, uint256 _amount) private {
        if(_index == 0) {
            totalTokenPoint0 = totalTokenPoint0.sub(_amount);
        }else {
            totalTokenPoint1 = totalTokenPoint1.sub(_amount);
        }
    }

    function _addUserStake(uint256 _index, address _user, uint256 _userPoint) private {
        UserInfo[] storage userDeposit = _index == 0? userInfo0[_user] : userInfo1[_user];

        (uint256 _lp, uint256 _reserve) = _tokenPerLp(_index);
        userDeposit.push(UserInfo({
            user: _user,
            tokenPoint: _userPoint,
            totalSupply: _lp,
            tokenReserve: _reserve
        }));
        if(_index == 0) {
            totalTokenPoint0 = totalTokenPoint0.add(_userPoint);
        } else {
            totalTokenPoint1 = totalTokenPoint1.add(_userPoint);
        }
    }
    function untakeLP(uint256 _index,uint256 _untakeLP) private returns (uint256 amountC, uint256 amountPaired) {
        
        (amountC, amountPaired) = stakeGatling.burn(address(this), _untakeLP);
        if(_index == 1) {
             (amountC , amountPaired) = (amountPaired, amountC);
        }
    }
    
    function token(uint256 _index) public view override returns (address) {
        return _index == 0 ? lpToken.token0() : lpToken.token1();
    }

    function lPAmount(uint256 _index, address _user) public view returns (uint256) {
        uint256 totalPoint = _index == 0? totalTokenPoint0 : totalTokenPoint1;
        return stakeGatling.totalLPAmount().mul(userPoint(_index, _user)).div(totalPoint);
    }

    function tokenAmount(uint256 _index, address _user) public view returns (uint256) {
        uint256 totalPoint = _index == 0? totalTokenPoint0 : totalTokenPoint1;
        uint256 pendingAmount = _index == 0? pendingToken0 : pendingToken1;

        uint256 userPoint = userPoint(_index, _user);
        return _userAmountByPoint(userPoint, totalPoint, pendingAmount);
    }

    function userPoint(uint256 _index, address _user) public view returns (uint256) {
        UserInfo[] storage stakeQueue = _index == 0? userInfo0[_user] : userInfo1[_user];
        uint256 userPoint;
        if(stakeQueue.length > 0) {
            uint256 stakeLength = stakeQueue.length;
            for (uint i=0; i < stakeLength; i++) {
                UserInfo storage user = stakeQueue[i];
                userPoint = userPoint.add(user.tokenPoint);
            }
        }
        return userPoint;
    }

    function _userAmountByPoint(uint256 _point, uint256 _totalPoint, uint256 _totalAmount ) 
        private pure returns (uint256) {
        if(_totalPoint == 0) {
            return 0;
        }
        return _point.mul(_totalAmount).div(_totalPoint);
    }

    function queueTokenAmount(uint256 _index) public view override  returns (uint256) {
        return _index == 0 ? pendingToken0: pendingToken1;
    }

    function totalTokenAmount(uint256 _index) public view  returns (uint256) {
        (uint256 amount0, uint256 amount1) = stakeGatling.totalToken();
        if(_index == 0) {
            return amount0.add(pendingToken0);
        }else {
            return amount1.add(pendingToken1);   
        }
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
        
        (uint256 amount0, uint256 amount1) = stakeGatling.totalToken();

        uint256 pendingTokenAmount = _index == 0 ? pendingToken0 : pendingToken1;
        uint256 lpTokenAmount =  _index == 0 ? amount0 : amount1;

        require(lpTokenAmount.mul(_molecular).div(_denominator) > pendingTokenAmount, "Amount in pool less than PendingAmount");
        uint256 maxAmount = lpTokenAmount.mul(_molecular).div(_denominator).sub(pendingTokenAmount);
        
        return _inputAmount > maxAmount ? maxAmount : _inputAmount ; 
    }

    /**
     * returns (TotalSupply, Reserves) to  make price currently
     *  _reservesCurrent.div(_totalSupply) may return float value which lost decimal part, convert 0.88 to 0
     */
    function _tokenPerLp(uint256 _index) private returns(uint256, uint256) {
        uint256 _totalSupply = lpToken.totalSupply();
        (uint256 _reservesCurrent, uint256 _reservesParied,) = lpToken.getReserves();    
        
        if(_index!=0) {
            _reservesCurrent = _reservesParied;
        }

        return (_totalSupply, _reservesCurrent);
    }

}
