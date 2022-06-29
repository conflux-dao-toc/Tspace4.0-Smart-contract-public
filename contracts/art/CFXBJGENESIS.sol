// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "../utils/StringUtils.sol";
import "../SponsorWhitelistControl.sol";
import "../owner/Operator.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract CFXBJGENESIS2021 is ERC1155, Operator {
    event CFXBJGENESISMint(address _onwer, uint256 _tokenId, string metedata);

    using Counters for Counters.Counter;
    //tokenid自增一
    Counters.Counter private _tokenIds;

    using SafeMath for uint256;

    // Contract name
    string public name = "CFXBJGENESIS";
    // Contract symbol
    string public symbol = "cfxbjgenesis";

    // Mapping from owner to list of owned token IDs
    mapping(address => uint256[]) private _ownedTokens;

    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) private _ownedTokensIndex;

    // Array with all token ids, used for enumeration
    uint256[] private _allTokens;

    // Mapping from token id to position in the allTokens array
    mapping(uint256 => uint256) private _allTokensIndex;

    string baseUri;

    mapping(uint256 => address[]) public ownerOfAddress;

    //tokenId => metadata
    mapping(uint256 => string) public tokenMetaData;

    //tokenId => FeatureCode, the Feature code is generally md5 code for resource files such as images or videos.
    mapping(uint256 => uint256) public tokenFeatureCode;

    uint256 public price = 5e18;

    SponsorWhitelistControl public constant SPONSOR =
        SponsorWhitelistControl(
            address(0x0888000000000000000000000000000000000001)
        );

    //设置baseUri,用来获取中心化服务
    constructor() public ERC1155("https://tspace-1253470014.cos.ap-hongkong.myqcloud.com/nft/cfxbjgenesis/metadata/") {
        baseUri = "https://tspace-1253470014.cos.ap-hongkong.myqcloud.com/nft/cfxbjgenesis/metadata/";

        //register all users as sponsees
        address[] memory users = new address[](1);
        users[0] = address(0);
        SPONSOR.addPrivilege(users);
    }

    // function setOracle(address _oracle) {}

    function setPrice(uint256 _price) public onlyOwner() {
        price = _price;
    }

    //重新设置 baseUri
    function setBaseUri(string memory _baseUri) public onlyOwner() {
        super._setURI(_baseUri);
        baseUri = _baseUri;
    }

    function isTokenOwner(address _owner, uint256 _id)
        public
        view
        returns (bool)
    {
        return balanceOf(_owner, _id) > 0;
    }

    function ownerOf(uint256 _id) public view returns (address[] memory) {
        return ownerOfAddress[_id];
    }

    function tokensOf(address _owner)
        public
        view
        returns (uint256[] memory _tokens)
    {
        return _ownedTokens[_owner];
    }

    //根据tokenId 获取 metadata
    function uri(uint256 _id) external view override returns (string memory) {
        return StringUtils.strConcat(baseUri, tokenMetaData[_id]);
    }

    /**
     * @dev Gets the total amount of tokens stored by the contract.
     * @return uint256 representing the total amount of tokens
     */
    function totalSupply() public view returns (uint256) {
        return _allTokens.length;
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        uint256 amount,
        bytes memory data
    ) public override {
        require(amount > 0, "Amount must > 0");
        super.safeTransferFrom(from, to, tokenId, amount, data);
        _removeTokenFromOwnerEnumeration(from, tokenId);
        _addTokenToOwnerEnumeration(to, tokenId);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual override {
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 tokenId = ids[i];
            uint256 amount = amounts[i];
            require(amount > 0, "Amount must > 0");
            _removeTokenFromOwnerEnumeration(from, tokenId);
            _addTokenToOwnerEnumeration(to, tokenId);
        }
    }

    /**
     * @dev Private function to add a token to this extension's ownership-tracking data structures.
     * @param to address representing the new owner of the given token ID
     * @param tokenId uint256 ID of the token to be added to the tokens list of the given address
     */
    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        _ownedTokensIndex[tokenId] = _ownedTokens[to].length;
        _ownedTokens[to].push(tokenId);
        address[] storage addr = ownerOfAddress[tokenId];
        if (addr.length > 0) {
            addr.pop();
        }
        addr.push(to);
    }

    /**
     * @dev Private function to add a token to this extension's token tracking data structures.
     * @param tokenId uint256 ID of the token to be added to the tokens list
     */
    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    function mint(string memory _metadataUri) public onlyOwner{
        //require(msg.value == price, "Value error");
        _tsMint(msg.sender, _metadataUri);
    }

    function addItem(address _to, string memory _metadataUri)
        public
        onlyMinter()
    {
        _tsMint(_to, _metadataUri);
    }

    //chy:tspace批量铸造方法，使用默认地址+id.json的方法，直接铸造amount个新的nft。
    function batchAddItemByNumber(address _to, uint256 _amount)
        public
        onlyMinter()
    {
        uint256 newItemId = _tokenIds.current()+1;
        for (uint i = 0; i < _amount; i++) {
            _tsMint(_to,StringUtils.strConcat(StringUtils.uint2str(newItemId+i),".json"));
        }
    }

    function batchAddItemByAddress(
        address[] calldata _initialOwners,
        string[] calldata _uris
    ) public onlyMinter() {
        require(_initialOwners.length == _uris.length, "uri length mismatch");
        
        uint256 _length = _uris.length;
        for (uint i = 0; i < _length; i++) {
            _tsMint(_initialOwners[i],_uris[i]);
        }
    }

    function _tsMint(address _to, string memory _metadataUri) internal {
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        tokenMetaData[newItemId] = _metadataUri;                                            
        _mint(
            _to,
            newItemId,
            1,
            bytes(StringUtils.strConcat(baseUri, _metadataUri))
        );
        _addTokenToAllTokensEnumeration(newItemId);
        _addTokenToOwnerEnumeration(_to, newItemId);
        emit CFXBJGENESISMint(_to, newItemId, _metadataUri);
    }

    receive() external payable {}

    function withdrawMain(uint256 _amount) public onlyOwner() {
        transferMain(msg.sender, _amount);
    }

    function transferMain(address _address, uint256 _value) internal {
        (bool res, ) = address(uint160(_address)).call{value: _value}("");
        require(res, "TRANSFER CFX ERROR");
    }

    /**
     * @dev Private function to remove a token from this extension's ownership-tracking data structures. Note that
     * while the token is not assigned a new owner, the `_ownedTokensIndex` mapping is _not_ updated: this allows for
     * gas optimizations e.g. when performing a transfer operation (avoiding double writes).
     * This has O(1) time complexity, but alters the order of the _ownedTokens array.
     * @param from address representing the previous owner of the given token ID
     * @param tokenId uint256 ID of the token to be removed from the tokens list of the given address
     */
    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId)
        private
    {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _ownedTokens[from].length.sub(1);
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];

            _ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        _ownedTokens[from].pop();

        // Note that _ownedTokensIndex[tokenId] hasn't been cleared: it still points to the old slot (now occupied by
        // lastTokenId, or just over the end of the array if the token was the last one).
        delete _ownedTokensIndex[tokenId];
    }

    /**
     * @dev Private function to remove a token from this extension's token tracking data structures.
     * This has O(1) time complexity, but alters the order of the _allTokens array.
     * @param tokenId uint256 ID of the token to be removed from the tokens list
     */
    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _allTokens.length.sub(1);
        uint256 tokenIndex = _allTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
        uint256 lastTokenId = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
        _allTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index

        // This also deletes the contents at the last position of the array
        _allTokens.pop();
        _allTokensIndex[tokenId] = 0;
    }

    //Optional functions：The feature code can only be set once for each id, and then it can never be change again。
    function setTokenFeatureCode(uint256 tokenId, uint256 featureCode) public onlyMinter() {
        require(tokenFeatureCode[tokenId] == 0, "NFT1.0: token Feature Code is already set up");
        tokenFeatureCode[tokenId] = featureCode;
    }
}
