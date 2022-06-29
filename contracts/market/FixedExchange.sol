pragma solidity ^0.6.2;
import "../owner/Operator.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import '../utils/AddressUtil.sol';
import "../SponsorWhitelistControl.sol";

contract FixedExchange is Operator,Pausable, ReentrancyGuard,IERC777Recipient{
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    Counters.Counter private _fixedIds;
    address public platform;

    //bought(成交),Sell(上架)
    event Buy(uint256 _fixedId, address _buyer, address _spendToken,uint256 _amount,
            address _nft,uint256 _tokenId,uint256 _fixedStatus);
    event Sell(uint256 _fixedId, address _seller, address _spendToken,uint256 _amount,
            address _nft,uint256 _tokenId,uint256 _fixedStatus,
            uint256 startTime,uint256 endTime);
    event Reverse(uint256 _fixedId,uint256 _fixedStatus);

    mapping(uint256 => FixedInfo) public fixedInfos;

    mapping(address => mapping(address => uint256)) public givers;

    //my bids 
    mapping(address => uint256[]) public myBidInfos;
    //my => auction id => index
    mapping(address => mapping(uint256 => uint256)) myBidInfoIndex;

    uint256[] fixedInfoList;

    uint256 public feeRate = 50;
    uint256 public basePersent = 1000;

    struct FixedInfo{
        uint256 fixedId;
        address nft;
        uint256 tokenId;
        address seller;
        address buyer;
        uint256 amount;
        address spendToken;
        uint32 fixedStatus; //0 on sell, 1 buy ,2 cancel
        uint256 startTime;
        uint256 endTime;
    }

    IERC1820Registry private _erc1820 = IERC1820Registry(0x88887eD889e776bCBe2f0f9932EcFaBcDfCd1820);

    // keccak256("ERC777TokensRecipient")
    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH =
        0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;

    SponsorWhitelistControl public constant SPONSOR = SponsorWhitelistControl(
        address(0x0888000000000000000000000000000000000001)
    );

    constructor() public{
        _erc1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
        platform = _msgSender();

        // register all users as sponsees
        address[] memory users = new address[](1);
        users[0] = address(0);
        SPONSOR.addPrivilege(users);
    }

    function getMyList(address _owner) view public returns(uint256[] memory){
        return myBidInfos[_owner];
    }

    function setPlatform(address _platform) public onlyOwner(){
        platform = _platform;
    }

    function setPlatFormRate(uint256 _rate) public onlyOwner(){
        feeRate = _rate;
    }

    function getFixedInfoList() view public returns (uint256[] memory _fixedInfoList) {
        return fixedInfoList;
    }

    function sell(address _nft,uint256 _tokenId, 
                address _spendToken, 
                uint256 _amount,
                uint256 _endTime) public whenNotPaused nonReentrant{
        require(AddressUtil.isContract(_spendToken) || _spendToken == address(0), "Spend token error");
        require(AddressUtil.isContract(_nft), "Nft address error");
        _fixedIds.increment();
        uint256 _fixedId = _fixedIds.current();
        FixedInfo storage fixedInfo = fixedInfos[_fixedId];
        fixedInfo.fixedId = _fixedId;
        fixedInfo.nft = _nft;
        fixedInfo.tokenId = _tokenId;
        fixedInfo.spendToken = _spendToken;
        fixedInfo.amount = _amount;
        fixedInfo.seller = _msgSender();
        fixedInfo.fixedStatus = 0;
        fixedInfo.startTime = block.timestamp;
        fixedInfo.endTime = _endTime;
        fixedInfoList.push(_fixedId);
        transfer1155(fixedInfo.nft,_msgSender(),address(this) ,fixedInfo.tokenId);
        _addMyAuction(_msgSender(),_fixedId);
        emit Sell(_fixedId, _msgSender(), _spendToken, _amount,_nft, _tokenId,0,fixedInfo.startTime,fixedInfo.endTime);
    }

    function buy(uint256 _fixedId,uint256 _amount) payable public whenNotPaused nonReentrant{
        FixedInfo storage fixedInfo = fixedInfos[_fixedId];
        require(fixedInfo.fixedStatus==0,"Not on sell");
        require(fixedInfo.seller!=address(0),"Id not exist");
        require(fixedInfo.endTime >= block.timestamp,"Sell over");
        if(fixedInfo.spendToken == address(0)){
            _amount = fixedInfo.amount;
            require(_amount == msg.value,"Pay amount error");
            transferMain(address(uint160(platform)),_amount.mul(feeRate).div(100),"Transfer to platform error");
            transferMain(address(uint160(fixedInfo.seller)),_amount.mul(100-feeRate).div(100),"Transfer to owner error");
        }else{
            require(_amount == fixedInfo.amount,"Pay token amount error");
            safeTransferFromToken(fixedInfo.spendToken,_msgSender(),platform, _amount.mul(feeRate).div(100));
            safeTransferFromToken(fixedInfo.spendToken,_msgSender(),fixedInfo.seller, _amount.mul(100-feeRate).div(100));
        }
        require(fixedInfo.seller != _msgSender(),"Not seller");
        //1155
        transfer1155(fixedInfo.nft, address(this),_msgSender(),fixedInfo.tokenId);
        fixedInfo.fixedStatus = 1;
        fixedInfo.buyer = _msgSender();
        _removeMyAuction(fixedInfo.seller,_fixedId);
        emit Buy(_fixedId,_msgSender(), fixedInfo.spendToken, fixedInfo.amount,fixedInfo.nft,fixedInfo.tokenId,1);
    }

    function reverse(uint256 _fixedId) public whenNotPaused nonReentrant{
        FixedInfo storage fixedInfo = fixedInfos[_fixedId];
        require(fixedInfo.fixedStatus == 0,"Not on sell");
        require(fixedInfo.seller!=address(0),"Id not exist");
        require(fixedInfo.seller == _msgSender(),"Not seller");
        transfer1155(fixedInfo.nft, address(this),_msgSender(),fixedInfo.tokenId);
        _removeMyAuction(_msgSender(),_fixedId);
        fixedInfo.fixedStatus = 2;
        emit Reverse(_fixedId,2);
    }


    function _addMyAuction(address _owner,uint256 _auctionId) internal{
        myBidInfoIndex[_owner][_auctionId] = myBidInfos[_owner].length;
        myBidInfos[_owner].push(_auctionId);
    }

    function _removeMyAuction(address _owner, uint256 _auctionId) internal{
        uint256 lastIndex = myBidInfos[_owner].length.sub(1);
        uint256 currentIndex = myBidInfoIndex[_owner][_auctionId];
        if(lastIndex != currentIndex){
            uint256 lastAuctionId = myBidInfos[_owner][lastIndex];
            myBidInfos[_owner][currentIndex] = lastAuctionId;
            myBidInfoIndex[_owner][lastAuctionId] = currentIndex;
        }
        myBidInfos[_owner].pop();
    }

    function transfer1155(address tnft, address _from,address _to,uint256 _tokenId) internal{
        IERC1155 iERC1155 = IERC1155(tnft);
        iERC1155.safeTransferFrom(_from,_to,_tokenId,1,"");
    }

    function transferMain(address _address, uint256 _value,string memory message) internal{
        (bool res, ) = address(uint160(_address)).call{value:_value}("");
        require(res,message);
    }

    function safeTransferFromToken(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        //transfer ERC20 Token
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FROM_FAILED');
    }

     //-----------
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    )external returns(bytes4){
       return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    )external returns(bytes4){
        return bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"));
    }

    function tokensReceived(
      address operator,
      address from,
      address to,
      uint amount,
      bytes calldata userData,
      bytes calldata operatorData
    ) external override{
        givers[operator][from] += amount;
    }

}