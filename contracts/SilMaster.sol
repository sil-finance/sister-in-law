pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./SilToken.sol";
import "./interfaces/IMatchPair.sol";
import './interfaces/IWETH.sol';
import './interfaces/IMintRegulator.sol';
import './TrustList.sol';

import "hardhat/console.sol";

// SilMaster is the master of Sil. He can make Sil and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SIL is sufficiently
// distributed and the community can show to govern itself.
//
