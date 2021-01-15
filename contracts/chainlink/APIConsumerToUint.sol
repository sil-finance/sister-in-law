pragma solidity ^0.6.12;

import "@chainlink/contracts/src/v0.6/ChainlinkClient.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IMintRegulator.sol";

contract APIConsumerToUint is ChainlinkClient, Ownable, IMintRegulator {
  
    uint256 public currentGas; // gas in Gwei
    uint256 public fee;
    uint256 public baseGasPrice;
    int256  public times;// request material
    //Last Request Time
    uint256  public lastUpdateTime;

    address public oracle; 
    string  public url;
    string  public path;
    bytes32 public jobId;

    event RequestLink(bytes32 _requestId);
    event FulFill(address _sender, bytes32 _requestId, uint256 _volume);
    event RequestSetting(address indexed _oracle, bytes32 _jobId, uint256 fee);
    constructor() public {
        setPublicChainlinkToken();
    }

    function setBaseGas(uint256 _baseGas) 
        public onlyOwner() 
    {
        baseGasPrice = _baseGas;
        lastUpdateTime = 0;
    }

    function getScale() 
        public view override 
        returns (uint256 _molecular, uint256 _denominator) 
    {
        //cannot be zero
        if(baseGasPrice * currentGas ==0) {
            return (1, 1);
        }
        // min 1/2
        if((baseGasPrice / currentGas) > 2) {
            return (1, 2);
        } 
        // max 2
        if((currentGas / baseGasPrice) > 2) {
            return (2, 1);
        } 
        
        return (baseGasPrice, currentGas);
    }
    
    /**
     * @dev setting request  material of ChainLink
     */
    function requestSetting( 
        address _oracle, 
        bytes32 _jobId, 
        string calldata _url, 
        string calldata _path, 
        int256 _times,
        uint256 _fee) 
        public onlyOwner()
        returns (bytes32 requestId) 
    {
        oracle = _oracle;
        jobId  = _jobId;
        url    = _url;
        path   = _path;
        times  = _times;  
        fee = _fee;
        // fee = 0.1 * 10 ** 18; // 0.1 LINK
        lastUpdateTime = 0;

        emit RequestSetting(_oracle, _jobId, _fee);
    }

    function requestScale() public
    {
        require(block.timestamp.sub(lastUpdateTime) > 0.5 days , "update per half-day");
        Chainlink.Request memory request = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);
        
        // Set the URL to perform the GET request on
        request.add("get", url);

        request.add("path", path);

        request.addInt("times", times);
        // Sends the request
        bytes32 requestId  = sendChainlinkRequestTo(oracle, request, fee);

        lastUpdateTime = block.timestamp;
        emit RequestLink(requestId);
    }

    /**
     * Receive the response in the form of uint256
     */ 
    function fulfill(bytes32 _requestId, uint256 _gas) 
        public recordChainlinkFulfillment(_requestId)
    {
        currentGas = _gas;

        emit FulFill(msg.sender, _requestId, _gas);
    }
}