pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./uniswapv2/interfaces/IUniswapV2Pair.sol";
import './uniswapv2/libraries/TransferHelper.sol';

import "./interfaces/IStakingRewards.sol";
import "./interfaces/IProfitStrategy.sol";



/**
 * mine FARM via Harvest.IStakingRewards
 * will transferOnwership to stakeGatling
 */
contract ProfitStrategyHarvest is Ownable, IProfitStrategy {

    //Uniswap StakeToken
    IStakingRewards stakeRewards;
    // UniLP ([usdt-eth].part)
    address public  stakeLpPair;
    //earnToken
    address private earnTokenAddr;
    address public stakeGatling;

    constructor (address _pair, address _stakeGatling) public {
        stakeLpPair = _pair;
        stakeGatling = _stakeGatling;
    }

    function setStakeToken(address _stakeToken, address _earnToken ) public onlyOwner() {
        require( address(stakeRewards) == address(0), "Only set once");
        stakeRewards =  IStakingRewards(_stakeToken);
        earnTokenAddr = _earnToken;
        TransferHelper.safeApprove(stakeLpPair, address(stakeRewards), ~uint256(0));
    }

     /**
     * Stake LP
     */
    function stake(uint256 _amount) external override onlyOwner() {
        
        if(address(stakeRewards) != address(0)) {
            //amount tranfer to address(this) in StakeGatling

            stakeRewards.stake(_amount);
        }
    }
    /**
     * withdraw LP
     */
    function withdraw(uint256 _amount) public override onlyOwner() {

        if(address(stakeRewards) != address(0) && _amount > 0) {
            stakeRewards.withdraw(_amount);
            TransferHelper.safeTransfer(stakeLpPair, stakeGatling, _amount);
        }
    }

    function burn(address _to, uint256 _amount) public override onlyOwner() returns (uint256 amount0, uint256 amount1) {

        if(address(stakeRewards) != address(0) && _amount > 0) {
            stakeRewards.withdraw(_amount);

            TransferHelper.safeTransfer(stakeLpPair, stakeLpPair, _amount);
            IUniswapV2Pair(stakeLpPair).burn(_to);
        }
    }

    function earn() external override onlyOwner() {
        stakeRewards.getReward();
        transferEarn2Gatling();
    }

    /**
     * withdraw LP && earnToken
     */
    function exit() external override  onlyOwner() {
        stakeRewards.exit();
        //transfer Assets to StakeGatling
        transferLP2Gatling();
        transferEarn2Gatling();
    }

    function stakeToken() external view override returns (address) {
        return address(stakeRewards);
    }

    function earnToken() external view override returns (address) {
        return earnTokenAddr;
    }

    function earnPending(address _account) external view override returns (uint256) {
        return stakeRewards.earned(_account);
    }
    function earnTokenBalance(address _account) external view override returns (uint256) {
        return IERC20(earnTokenAddr).balanceOf(_account);
    }

    function balanceOfLP(address _account) external view override  returns (uint256) {
        return stakeRewards.balanceOf(_account);
    }
    
    function transferLP2Gatling() private {

        uint256 _lpAmount = IERC20(stakeLpPair).balanceOf(address(this));
        if(_lpAmount > 0) {
            TransferHelper.safeTransfer(stakeLpPair, stakeGatling, IERC20(stakeLpPair).balanceOf(address(this)));
        }
    }
    function transferEarn2Gatling() private {

        uint256 _tokenAmount = IERC20(earnTokenAddr).balanceOf(address(this));
        if(_tokenAmount > 0) {
            TransferHelper.safeTransfer(earnTokenAddr, address(stakeGatling), _tokenAmount);
        }
    }
}