pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./utils/ERC1967Proxy.sol";

import "./storage/StrategySushiStorage.sol";



/**
 * mine SUSHI via SUSHIswap.MasterChef
 * will transferOnwership to stakeGatling
 */
contract ProfitStrategySushiProxy is StrategySushiStorage, Ownable , ERC1967Proxy {

    constructor (address  _delegate, address _pair, uint256 _pid, address _stakeGatling)  ERC1967Proxy(_delegate, '')  public {
        stakeLpPair = _pair;
        stakeGatling = _stakeGatling;
        pid = _pid;
        safeApprove(stakeLpPair, address(stakeRewards), ~uint256(0));
        transferOwnership(_stakeGatling);
    }

    function safeApprove(address token, address to, uint value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

}