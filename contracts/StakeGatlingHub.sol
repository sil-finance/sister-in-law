pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./uniswapv2/interfaces/IUniswapV2Pair.sol";
import './uniswapv2/libraries/UniswapV2Library.sol';
import './uniswapv2/libraries/TransferHelper.sol';

import "./utils/MasterCaller.sol";
import "./interfaces/IUniswapV2Router01.sol";
import "./interfaces/IStakingRewards.sol";
import "./interfaces/IStakeGatling.sol";
import "./interfaces/IProfitStrategy.sol";



contract StakeGatlingHub is Ownable, IStakeGatling, MasterCaller {
    using SafeERC20 for IERC20;

    using SafeMath for uint256; 

    // UniLP ([usdt-eth].part)
    IUniswapV2Pair public  stakeLpPair;

    IProfitStrategy public profitStrategy;

    // MatchPair.address
    address public matchPair;
    // Uniswsap V2Router
    address public v2Router;

    uint256 public totalAmount;
    uint256 public _presentRate = 1e18;
    uint256 public _profitRateDenominator = 1e18;

    uint256 public reprofitCountTotal;
    uint256 public createAt;
    //Update every half day by default
    uint256 public updatesPerDay = 4;
    uint256 public updatesMin;
    uint256 profitRateUpdateTime;

    address[] routerPath0;
    address[] routerPath1;

    struct ProfitRateHis {
        uint256 day;
        uint256 profitRateHis;
    }
    ProfitRateHis[] public profitRateHis;
    mapping(uint256 => uint256) public reprofitCount;

    event ProfitStrategyEvent(address _profitStrategy);

    constructor (address _pair) public {
        stakeLpPair = IUniswapV2Pair(_pair);
        createAt = now;
    }

    function setMatchPair(address _matchPair) public onlyOwner() {
        matchPair = _matchPair;
        transferMastership(_matchPair);
    }

    function setUpdatesRule(uint256 _updatesPerDay, uint256  _updatesMin) public onlyOwner() {
        updatesPerDay = _updatesPerDay;
        updatesMin = _updatesMin;
    }

    function setRouter(address _v2Router ) public onlyOwner() {
        if(v2Router != _v2Router) {
            v2Router = _v2Router;
        }
    }

    function setProfitStrategy(address _profitStrategy) public onlyOwner() {

        if(address(profitStrategy) != address(0)) {
            profitStrategy.earn();
            uint256 _minedAmount = profitStrategy.earnTokenBalance(address(this));
            if (_minedAmount > 0) {
                _execReprofit();   
            }
            //retrieve LP and Token;
            profitStrategy.exit();
        }
        profitStrategy = IProfitStrategy(_profitStrategy);
        if(_profitStrategy != address(0)) {
            //Stake to new profitStrategy
            uint256 _amount =  stakeLpPair.balanceOf(address(this));
            if(_amount > 0) {
                TransferHelper.safeTransfer(address(stakeLpPair), _profitStrategy, _amount);
                profitStrategy.stake(_amount);
            }
        }
        emit ProfitStrategyEvent(_profitStrategy);
    }

    function setRouterPath(uint256 _tokenSide, address[] calldata path ) public onlyOwner() {

        if(_tokenSide == 0 && routerPath0.length > 0) {
            delete routerPath0;
        } 
        if(_tokenSide == 1 && routerPath1.length > 0) {
            delete routerPath1;
        }
        _approvePath(path, _tokenSide);
    }

    function _approvePath( address[] calldata path, uint256 _tokenSide) private {

        address[] storage routerPath = _tokenSide == 0? routerPath0: routerPath1;

        for (uint i=0; i< path.length; i++) {

            address _erc20Token = path[i];
            routerPath.push(_erc20Token);
            _approveWithCheck(_erc20Token, v2Router);
        }
    }
    function _approveWithCheck(address _erc20Token, address _spender) private  {
        if( IERC20(_erc20Token).allowance(address(this), _spender) == 0 ) {
            TransferHelper.safeApprove(_erc20Token, _spender, ~uint256(0));
        }
    }

    function stake(uint256 _amount) external override onlyMasterCaller() {

        if(address(profitStrategy) != address(0)) {
            updateRate();
            profitStrategy.stake(_amount);
        }
        totalAmount = totalAmount.add(_amount);
    }

    function withdraw(uint256 _amount) public override onlyMasterCaller() {

        if(address(profitStrategy) != address(0)) {
            updateRate();
            if(_amount > 0) {
                profitStrategy.withdraw(_amount);
            }
        }
        if(_amount > 0 ) {

            TransferHelper.safeTransfer(address(stakeLpPair), address(matchPair),_amount);
            totalAmount = totalAmount.sub(_amount);
        }
        
    }
    function burn(address _to, uint256 _amount) external override returns (uint256 amount0, uint256 amount1) {
        if(address(profitStrategy) != address(0)) {
            updateRate();
            if(_amount > 0) {
                (amount0, amount1) = profitStrategy.burn(_to, _amount);
                totalAmount = totalAmount.sub(_amount);
            }
        }else {
            TransferHelper.safeTransfer(address(stakeLpPair), address(stakeLpPair), _amount);
            (amount0, amount1) =  stakeLpPair.burn(_to);
        }
    }

    function updateRate() private {
        // 1. get earned
        profitStrategy.earn();
        uint256 _minedAmount = profitStrategy.earnTokenBalance(address(this));
        
        if( _minedAmount > updatesMin && (now.sub(profitRateUpdateTime).mul(updatesPerDay) >= (1 days)) ) {
            _execReprofit();
        }
    }

    function _execReprofit() private {
        // 2. sell earnToken to TokenA/ TokenB
        sellEarn2TokenTwice();
        // 3. mint LP
        uint256 liquidity = mintLP();

        // 4. update contract rate
        if(liquidity > 0) {
            _presentRate = _presentRate.mul(totalAmount.add(liquidity)).div(totalAmount);
            totalAmount = totalAmount.add(liquidity);
            profitStrategy.stake(liquidity);
        }

        uint today = now.div(1 days).add(1);
        mapping(uint256 => uint256) storage  _reprofitCount = reprofitCount;

        if(_reprofitCount[today] == 0) { // daliy first calculate
            profitRateHis.push(ProfitRateHis(today, _presentRate ));
        }
        _reprofitCount[today] = _reprofitCount[today] + 1;
        reprofitCountTotal = reprofitCountTotal +1;
        
        profitRateUpdateTime = now;
    }

    function currentProfitRate() public view returns (uint256, uint256) {
        ProfitRateHis[]  storage _profitRateHis = profitRateHis;
        uint256 length = _profitRateHis.length;
        if(length == 0) {
            return (0, 0);
        }else if(length == 1) {
            return (_profitRateHis[0].profitRateHis, 1);
        }else {
            uint interval = _profitRateHis[length-1].day - _profitRateHis[length-2].day;
            return (_profitRateHis[length-1].profitRateHis.mul(1e18).div(_profitRateHis[length-2].profitRateHis), interval);
        }
    }

    function sellEarn2TokenTwice() private returns (address _tokenAddress) {

        (address _token0, address _token1) = (stakeLpPair.token0(), stakeLpPair.token1());

        uint256 _minedAmount = profitStrategy.earnTokenBalance(address(this));
        address earnToken = profitStrategy.earnToken();
        if(_token0 != earnToken) {
            execSell(_minedAmount.div(2), 0);
        }
        if(_token1 != earnToken) {
            execSell(_minedAmount.div(2), 1);
        }
    }

    function execSell(uint256 _amount, uint256 _tokenSide) private {
        
        address[] memory path = _tokenSide == 0? routerPath0 : routerPath1;
        IUniswapV2Router01(v2Router).swapExactTokensForTokens( _amount, 0, path, address(this), now.add(60000) );
    }

    /**
     *  mintLP
     */
    function mintLP() private returns (uint256 liquidity) {

        (address _token0, address _token1) = (stakeLpPair.token0(), stakeLpPair.token1());
        address _addrThis = address(this);

        uint balance0 = IERC20(_token0).balanceOf(_addrThis);
        uint balance1 = IERC20(_token1).balanceOf(_addrThis);


        if(balance0 > 0 && balance1 > 0) {
            //recalculate Amount0 Amoutn1 via TransactionHelper
            (uint amount0, uint amount1)  =  getPairAmount(balance0, balance1);
            TransferHelper.safeTransfer(_token0, address(stakeLpPair), amount0);
            TransferHelper.safeTransfer(_token1, address(stakeLpPair), amount1);
            //mint
            liquidity = stakeLpPair.mint(address(profitStrategy));
        }
    }

    /**  View Function */

    function presentRate() public view override returns (uint256) {
        return _presentRate;
    }

    function reprofitCountAverage() public view returns (uint256) {
        return reprofitCountTotal.div(now.sub(createAt).div(1 days));
    }

    function getPairAmount(
        uint amountADesired,
        uint amountBDesired  ) public view returns ( uint amountA, uint amountB) {
            
        (uint reserveA, uint reserveB,) = stakeLpPair.getReserves();

        uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
        if (amountBOptimal <= amountBDesired) {
            (amountA, amountB) = (amountADesired, amountBOptimal);
        } else {
            uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
            assert(amountAOptimal <= amountADesired);
            (amountA, amountB) = (amountAOptimal, amountBDesired);
        }
    }

    function profitRateDenominator() public override view returns(uint256) {
        return _profitRateDenominator;
    }

    function totalLp() public view returns (uint256 balance) {
        balance = profitStrategy.balanceOfLP(address(profitStrategy));
    }

    function totalToken() public view override returns (uint256 amount0, uint256 amount1) {
        //
        (uint112 _reserve0, uint112 _reserve1,) = stakeLpPair.getReserves();
        uint256 liquidity = profitStrategy.balanceOfLP(address(this));
        uint256 _totalSupply = stakeLpPair.totalSupply();

        amount0 = liquidity.mul(_reserve0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(_reserve1) / _totalSupply;
    }

    function lpStakeDst() public view override returns (address) {
        address _profitStrategy = address(profitStrategy);
        return address(profitStrategy) == address(0)? address(this) : _profitStrategy;
    }

}