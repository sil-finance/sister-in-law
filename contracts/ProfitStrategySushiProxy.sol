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

    modifier ifAdmin() {
        require (msg.sender == admin, "Admin require");
        _;
    }

    constructor (address  _delegate, address _admin,  address _pair, uint256 _pid, address _stakeGatling)  ERC1967Proxy(_delegate, '')  public {
        stakeLpPair = _pair;
        stakeGatling = _stakeGatling;
        pid = _pid;
        safeApprove(stakeLpPair, address(stakeRewards), ~uint256(0));
        transferOwnership(_stakeGatling);
        admin = _admin;
    }

    function safeApprove(address token, address to, uint value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function upgradeTo(address newImplementation) external ifAdmin() {
        _upgradeTo(newImplementation);
    }

    function changeAdmin(address newAdmin) external ifAdmin() {
        emit AdminChanged(admin, newAdmin); 
        admin = newAdmin;
    }

}