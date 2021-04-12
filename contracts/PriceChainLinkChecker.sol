pragma solidity 0.6.12;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IPriceSafeChecker.sol";



contract PriceChainLinkChecker is IPriceSafeChecker, Ownable {
    using SafeMath for uint256; 

    // 1WETH = 1021 USDT, Token1 = WETH; Price = Rusdt/ Reth
    bool public token1Direct;
    uint256 public immutable decimals;
    // min price 9/10
    uint256 public minPriceNumerator;
    uint256 public minPriceDenominator;
    // max price 11/10
    uint256 public maxPriceNumerator;
    uint256 public maxPriceDenominator;

    AggregatorV3Interface internal priceFeed;

    /**
     * _oracle : chainLink Oracle address
     * _token1Direct: Token0 in LP is token-base. ex: USDT/ETH, ETH is token1, _token1Direct = false
     */
    constructor(address _oracle, bool _token1Direct) public {
        priceFeed = AggregatorV3Interface(_oracle);
        token1Direct = _token1Direct;
        uint256 decimal = priceFeed.decimals();
        decimals = uint256(10)**decimal;
    }

    /**
     * Returns the latest price
     */
    function getLatestPrice() public view returns (uint256) {
        (
            , 
            int price,
            ,
            ,
        ) = priceFeed.latestRoundData();
        return uint256(price);
    }

    function checkPrice(uint256 _reserve0, uint256 _reserve1) external view override {

        (uint256 reserveDirect, uint256 reserveBased) =  token1Direct? (_reserve0, _reserve1):( _reserve1, _reserve0);
        // currentPrice = ETHReserve * decimals / TokenReserve
        uint256 currentPrice = reserveDirect.mul(decimals).div(reserveBased);
        uint256 trustedPrice = getLatestPrice();

        require(currentPrice.mul(maxPriceDenominator) <= trustedPrice.mul(maxPriceNumerator), "Hight risk: Overpriced!");
        require(trustedPrice.mul(minPriceNumerator) <= currentPrice.mul(minPriceDenominator), "Hight risk: Price is too low!");
    }

    function setToken1Direct(bool _token1Direct) external  onlyOwner() {
        token1Direct = _token1Direct;
    }
    function setPriceRange(
        uint256 _minPriceNumerator, 
        uint256 _minPriceDenominator,
        uint256 _maxPriceNumerator,
        uint256 _maxPriceDenominator
        )
        public 
        onlyOwner()
    {
        minPriceNumerator = _minPriceNumerator;
        minPriceDenominator = _minPriceDenominator;

        maxPriceNumerator = _maxPriceNumerator;
        maxPriceDenominator = _maxPriceDenominator;

        emit SettingPriceRang(_minPriceNumerator, _minPriceDenominator, _maxPriceNumerator, _maxPriceDenominator);
    }
}