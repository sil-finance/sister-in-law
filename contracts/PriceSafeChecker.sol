pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IPriceSafeChecker.sol";



contract PriceSafeChecker is IPriceSafeChecker, Ownable {
    using SafeMath for uint256; 

    // 1WETH = 1021 USDT, Token1 = WETH; Price = Rusdt/ Reth
    bool public token1Direct;
    // min price 9/10
    uint256 public minPriceNumerator;
    uint256 public minPriceDenominator;

    // max price 11/10
    uint256 public maxPriceNumerator;
    uint256 public maxPriceDenominator;

    uint256 public trustedPrice;

    event FeedPrice(uint256 _price);
    // event SettingPriceRang(uint256 _minPriceNumerator, uint256 _minPriceDenominator, uint256 _maxPriceNumerator, uint256 _maxPriceDenominator);

    constructor(bool _token1Direct) public {
        token1Direct = _token1Direct;
    }

    function checkPrice(uint256 _reserve0, uint256 _reserve1) external view override  {

        (uint256 reserveDirect, uint256 reserveBased) =  token1Direct? (_reserve0, _reserve1):( _reserve1, _reserve0);

        // currentPrice
        uint256 currentPrice = reserveDirect.div(reserveBased);
        // uint256 trustedPrice = getLatestPrice();
        require(currentPrice.mul(maxPriceDenominator) <= trustedPrice.mul(maxPriceNumerator), "Hight risk: Overpriced!");
        require(trustedPrice.mul(minPriceNumerator) <= currentPrice.mul(minPriceDenominator), "Hight risk: Price is too low!");
    }

    function getLatestPrice() public view returns (uint256) {
        return trustedPrice;
    }

    function feedPrice(uint256 _feedPrice) public onlyOwner() {
        trustedPrice = _feedPrice;
        emit FeedPrice(_feedPrice);
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