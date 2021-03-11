pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./uniswapv2/interfaces/IUniswapV2Pair.sol";
import './uniswapv2/libraries/TransferHelper.sol';
import "./utils/MasterCaller.sol";
import "./interfaces/IProfitStrategy.sol";



interface IMasterChef {

    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function pendingSushi(uint256 _pid, address _user) external view returns (uint256);
    function userInfo(uint256 _pid, address _user) external view returns (UserInfo memory _userInfo);
}
/**
 * mine SUSHI via SUSHIswap.MasterChef
 * will transferOnwership to stakeGatling
 */
contract ProfitStrategySushi is Ownable, IProfitStrategy {

    //Sushi MasterChef
    IMasterChef stakeRewards;
    // UniLP ([usdt-eth].part)
    address public  stakeLpPair;
    //earnToken
    address private earnTokenAddr;
    address public stakeGatling;

    uint256 public pid;

    constructor (address _pair, address _stakeGatling) public {
        stakeLpPair = _pair;
        stakeGatling = _stakeGatling;
    }

    function setStakeToken(address _stakeToken, address _earnToken, uint256 _pid ) public onlyOwner() {
        require( address(stakeRewards) == address(0), "Only set once");
        stakeRewards =  IMasterChef(_stakeToken);
        earnTokenAddr = _earnToken;
        pid = _pid;
        
        TransferHelper.safeApprove(stakeLpPair, address(stakeRewards), ~uint256(0));
    }
     /**
     * Stake LP
     */
    function stake(uint256 _amount) external override onlyOwner() {
        
        if(address(stakeRewards) != address(0)) {
            stakeRewards.deposit( pid, _amount);
        }
    }
    /**
     * withdraw LP
     */
    function withdraw(uint256 _amount) public override onlyOwner() {

        if(address(stakeRewards) != address(0) && _amount > 0) {

            stakeRewards.withdraw(pid, _amount);
            TransferHelper.safeTransfer(stakeLpPair, address(stakeGatling),_amount);
        }
    }

    function burn(address _to, uint256 _amount) external override onlyOwner() returns (uint256 amount0, uint256 amount1) {

        if(address(stakeRewards) != address(0) && _amount > 0) {
            stakeRewards.withdraw(pid, _amount);
            TransferHelper.safeTransfer(stakeLpPair, stakeLpPair, _amount);
            (amount0, amount1) =  IUniswapV2Pair(stakeLpPair).burn(_to);
        }
    }

    function stakeToken() external view override returns (address) {
        return address(stakeRewards);
    }

    function earnToken() external view override returns (address) {
        return earnTokenAddr;
    }

    function earnPending(address _account) external view override returns (uint256) {
        return stakeRewards.pendingSushi(pid, _account);
    }
    function earn() external override onlyOwner() {
        stakeRewards.deposit(pid, 0);
        transferEarn2Gatling();
    }
    function earnTokenBalance(address _account) external view override returns (uint256) {
        return IERC20(earnTokenAddr).balanceOf(_account);
    }

    function balanceOfLP(address _account) external view override  returns (uint256) {
        //
        return stakeRewards.userInfo(pid, _account).amount;
    }
    
    /**
     * withdraw LP && earnToken
     */
    function exit() external override  onlyOwner() {

        withdraw(stakeRewards.userInfo(pid, address(this)).amount);
        transferLP2Gatling();
        transferEarn2Gatling();
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