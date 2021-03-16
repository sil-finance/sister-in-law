pragma solidity 0.6.12;

/**
 * mine SUSHI via SUSHIswap.MasterChef
 * will transferOnwership to stakeGatling
 */
contract StrategySushiStorage {

    //Sushi MasterChef
    address public stakeRewards = 0x8184b47518Fef40ad5E03EbDE2f6d6bde2FA1B33 ;//= 0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd;
    // UniLP ([usdt-eth].part)
    address public  stakeLpPair;
    //earnToken
    address public earnTokenAddr = 0x1A63bBB6E16f7Fc7D34817496985757CD550c2c0  ;//= 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;
    address public stakeGatling;
    uint256 public pid;

}