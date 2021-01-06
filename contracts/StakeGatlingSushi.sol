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

import "hardhat/console.sol";
