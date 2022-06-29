// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity ^0.6.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../libs/LibOrder.sol";
import "../libs/LibSignatureValidator.sol";
import "../utils/SafeDecimalMath.sol";
import "./IExchange.sol";
import "../owner/Operator.sol";

import "../SponsorWhitelistControl.sol";

contract FixedExchangeV2 is
    Ownable,
    Pausable,
    ReentrancyGuard,
    LibOrder,
    LibSignatureValidator,
    Operator
{
    using SafeMath for uint256;
    using SafeDecimalMath for uint256;

    struct FillResults {
        uint256 tradePrice;
        uint256 fee;
        uint256 contractFee;
    }

    uint256 public constant MAX_CONTRACT_FEE = 3 * 10**17; // 30%
    uint256 public constant FEE_UPDATE_COOLDOWN = 1 days;

    //tokenId => on sale
    mapping(address => mapping(uint256 => bool)) public onSale;
    // Mapping of orderHash => created
    mapping(bytes32 => bool) public created;

    // Mapping of orderHash => filled
    mapping(bytes32 => bool) public filled;

    // Mapping of orderHash => cancelled
    mapping(bytes32 => bool) public cancelled;

    uint256 public contractFeePercentage;
    address public contractFeeRecipient;
    uint256 public mostRecentTimestamp;
    IExchange iExchange;
    SponsorWhitelistControl public constant SPONSOR =
        SponsorWhitelistControl(
            address(0x0888000000000000000000000000000000000001)
        );

    constructor(uint256 _contractFeePercentage, address _contractFeeRecipient)
        public
    {
        setContractFeeParams(_contractFeePercentage, _contractFeeRecipient);

        //register all users as sponsees
        address[] memory users = new address[](1);
        users[0] = address(0);
        SPONSOR.addPrivilege(users);
    }

    function setEnglishExchange(IExchange _iExchange) public onlyOwner {
        iExchange = _iExchange;
    }

    function getPrice(OrderFixed memory order) public pure returns (uint256) {
        return order.startPrice;
    }

    function setContractFeeParams(
        uint256 _contractFeePercentage,
        address _contractFeeRecipient
    ) public onlyOwner {
        require(
            mostRecentTimestamp.add(FEE_UPDATE_COOLDOWN) < block.timestamp,
            "in cooldown"
        );
        require(_contractFeePercentage <= MAX_CONTRACT_FEE, "exceed max fee");

        contractFeePercentage = _contractFeePercentage;
        contractFeeRecipient = _contractFeeRecipient;
        mostRecentTimestamp = block.timestamp;

        emit ContractFeeParamsUpdated(
            msg.sender,
            _contractFeePercentage,
            _contractFeeRecipient
        );
    }

    // chy:新增下架函数，用于后台清理不用的数据
    function setOffSale(address _assetAddress, uint256 _id) public onlyManager {
        onSale[_assetAddress][_id] = false;
    }

    // chy:新增修饰判断，是否为卖家
    modifier sellerOnly(OrderFixed memory order){
        require(msg.sender == order.owner, "msg.sender is not the order owner.");
        _;
    }

    //create
    function createOrder(OrderFixed memory order, bytes memory signature)
        public
        whenNotPaused
        nonReentrant
        sellerOnly(order)
        returns (bool)
    {
        return _createOrder(order, signature);
    }

    //reverse
    function reverseOrder(OrderFixed memory order)
        public
        whenNotPaused
        nonReentrant
        sellerOnly(order)
        returns (bool)
    {
        return _reverseOrder(order);
    }

    //buy
    function fillOrder(OrderFixed memory order, bytes memory signature)
        public
        payable
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        if (order.currencyAddress == address(0x0000000000000000000000000000000000000000)) {
            require(msg.value == order.startPrice,"Value sent not equals price.");
        }
        return _fillOrder(order, signature);
    }

    //create
    function createOrderFT(OrderFixed memory order, bytes memory signature)
        public
        whenNotPaused
        nonReentrant
        sellerOnly(order)
        returns (bool)
    {
        return _createOrderFT(order, signature);
    }

    //reverse
    function reverseOrderFT(OrderFixed memory order)
        public
        whenNotPaused
        nonReentrant
        sellerOnly(order)
        returns (bool)
    {
        return _reverseOrderFT(order);
    }

    //buy
    function fillOrderFT(
        OrderFixed memory order,
        bytes memory signature
    ) public payable whenNotPaused nonReentrant returns (bool) {
        if (order.currencyAddress == address(0x0000000000000000000000000000000000000000)) {
            require(msg.value == order.startPrice,"Value sent not equals price.");
        }
        return _fillOrderFT(order, signature);
    }

    function _createOrder(OrderFixed memory order, bytes memory signature)
        internal
        returns (bool)
    {
        // Get order info
        OrderInfo memory orderInfo = getOrderInfo(order);
        require(!onSale[order.assetAddress][order.id], "Nft id has on sale");
        onSale[order.assetAddress][order.id] = true;
        require(!created[orderInfo.orderHash], "Has created");
        require(
            !iExchange.onSale(order.assetAddress, order.id),
            "Nft id has on english exchange"
        );
        _assertFillableOrder(order, orderInfo, signature);
        //Owner is msg sender
        order.owner = msg.sender;
        order.taker = address(0);

        FillResults memory fillResults = calculateFillResults(order);
        // Update exchange state
        _updateCreatedStates(order, orderInfo, fillResults);

        return true;
    }

    function _reverseOrder(OrderFixed memory order) internal returns (bool) {
        // Get order info
        OrderInfo memory orderInfo = getOrderInfo(order);
        //Owner is msg sender
        order.owner = order.owner == address(0) ? msg.sender : order.owner;
        order.taker = address(0);
        require(onSale[order.assetAddress][order.id], "Nft id not on sale");
        onSale[order.assetAddress][order.id] = false;
        // Update exchange state
        _updateReverseStates(order, orderInfo);

        return true;
    }

    function _fillOrder(OrderFixed memory order, bytes memory signature)
        internal
        returns (bool)
    {
        // Get order info 获取真实的order
        OrderInfo memory orderInfo = getOrderInfo(order);
        require(created[orderInfo.orderHash], "Not created");
        require(onSale[order.assetAddress][order.id], "Nft id not on sale");
        onSale[order.assetAddress][order.id] = false;
        // Assert context is valid or we revert
        _assertFillableOrder(order, orderInfo, signature);

        // Compute proportional fill amounts
        FillResults memory fillResults = calculateFillResults(order);

        order.owner = order.owner == address(0) ? msg.sender : order.owner;
        order.taker = order.taker == address(0) ? msg.sender : order.taker;

        // Update exchange state
        _updateFilledStates(order, orderInfo, fillResults);

        // Settle matched orders. Succeeds or throws.
        _settleTrade(order, fillResults);

        return true;
    }

    function _createOrderFT(OrderFixed memory order, bytes memory signature)
        internal
        returns (bool)
    {
        // Get order info
        OrderInfo memory orderInfo = getOrderInfo(order);
        //require(!onSale[order.assetAddress][order.id], "Nft id has on sale");
        //onSale[order.assetAddress][order.id] = true;
        require(!created[orderInfo.orderHash], "Has created");
        // require(
        //     !iExchange.onSale(order.assetAddress, order.id),
        //     "Nft id has on english exchange"
        // );
        _assertFillableOrder(order, orderInfo, signature);
        //Owner is msg sender
        order.owner = msg.sender;
        order.taker = address(0);

        FillResults memory fillResults = calculateFillResults(order);
        // Update exchange state
        _updateCreatedStatesFT(order, orderInfo, fillResults);

        return true;
    }

    function _reverseOrderFT(OrderFixed memory order) internal returns (bool) {
        // Get order info
        OrderInfo memory orderInfo = getOrderInfo(order);
        //Owner is msg sender
        order.owner = order.owner == address(0) ? msg.sender : order.owner;
        order.taker = address(0);
        //require(onSale[order.assetAddress][order.id], "Nft id not on sale");
        onSale[order.assetAddress][order.id] = false;
        // Update exchange state
        _updateReverseStatesFT(order, orderInfo);

        return true;
    }

    function _fillOrderFT(
        OrderFixed memory order,
        bytes memory signature
    ) internal returns (bool) {
        // Get order info 获取真实的order
        OrderInfo memory orderInfo = getOrderInfo(order);
        require(created[orderInfo.orderHash], "Not created");
        //require(onSale[order.assetAddress][order.id], "Nft id not on sale");
        //onSale[order.assetAddress][order.id] = false;
        // Assert context is valid or we revert
        _assertFillableOrder(order, orderInfo, signature);

        // Compute proportional fill amounts
        FillResults memory fillResults = calculateFillResults(order);

        order.owner = order.owner == address(0) ? msg.sender : order.owner;
        order.taker = order.taker == address(0) ? msg.sender : order.taker;

        // Update exchange state
        _updateFilledStatesFT(order, orderInfo, fillResults);

        // Settle matched orders. Succeeds or throws.
        _settleTradeFT(order, fillResults);

        return true;
    }

    function getFixedHash(OrderFixed memory order)
        public
        view
        returns (bytes32 orderHash)
    {
        return getOrderFixedHash(order);
    }

    function getOrderInfo(OrderFixed memory order)
        internal
        view
        returns (OrderInfo memory orderInfo)
    {
        // Compute the order hash 根据order生成hash
        orderInfo.orderHash = getOrderFixedHash(order);

        // Fetch operated amount
        orderInfo.filled = filled[orderInfo.orderHash];

        // Validate the order price
        if (order.orderType >= uint256(OrderType.INVALID_TYPE)) {
            orderInfo.orderStatus = OrderStatus.INVALID;
            return orderInfo;
        }

        // Validate the order amount
        // if (order.amount == 0) {
        //     orderInfo.orderStatus = OrderStatus.INVALID;
        //     return orderInfo;
        // }

        // Validate the sender's identity
        if (order.operator != address(0) && order.operator != msg.sender) {
            orderInfo.orderStatus = OrderStatus.INVALID_OPERATOR;
            return orderInfo;
        }

        if (order.feePercentage > uint256(30**17)) {
            orderInfo.orderStatus = OrderStatus.INVALID;
            return orderInfo;
        }

        // Validate order availability
        if (orderInfo.filled) {
            orderInfo.orderStatus = OrderStatus.FILLED;
            return orderInfo;
        }

        // Validate if order is cancelled
        if (cancelled[orderInfo.orderHash]) {
            orderInfo.orderStatus = OrderStatus.CANCELLED;
            return orderInfo;
        }

        // All other statuses are ruled out: order is Fillable
        orderInfo.orderStatus = OrderStatus.FILLABLE;
        return orderInfo;
    }

    function _assertFillableOrder(
        OrderFixed memory order,
        OrderInfo memory orderInfo,
        bytes memory signature
    ) internal pure {
        require(orderInfo.orderStatus != OrderStatus.INVALID, "INVALID");
        require(orderInfo.orderStatus != OrderStatus.FILLED, "FILLED");
        require(orderInfo.orderStatus != OrderStatus.EXPIRED, "EXPIRED");
        require(orderInfo.orderStatus != OrderStatus.CANCELLED, "CANCELLED");
        require(
            orderInfo.orderStatus != OrderStatus.INVALID_OPERATOR,
            "INVALID_OPERATOR"
        );
        require(
            orderInfo.orderStatus == OrderStatus.FILLABLE,
            "ORDER_UNFILLABLE"
        );

        // Validate creator signature chy 改成了created 因为目前传的是0 为了让前端少改一个地方
        if (order.orderType == uint256(OrderType.CREATE)) {
            // If currency owner is zero address, this is a fixed-price sale created by asset owner
            require(
                isValidSignature(orderInfo.orderHash, order.owner, signature),
                "INVALID_ORDER_SIGNATURE"
            );
        }

        // Validate creator signature
        // if (order.orderType == uint256(OrderType.SALE)) {
        //     // If currency owner is zero address, this is a fixed-price sale created by asset owner
        //     require(
        //         isValidSignature(orderInfo.orderHash, order.owner, signature),
        //         "INVALID_ORDER_SIGNATURE"
        //     );
        // }
    }

    function _assertValidCancel(
        OrderFixed memory order,
        OrderInfo memory orderInfo
    ) internal view {
        require(
            orderInfo.orderStatus != OrderStatus.INVALID_OPERATOR,
            "INVALID_OPERATOR"
        );

        // Validate transaction signed by the creator
        if (order.orderType == uint256(OrderType.SALE)) {
            // If currency owner is zero address, this is a fixed-price sale created by asset owner
            require(order.owner == msg.sender, "INVALID_OWNER");
        }

        if (order.orderType == uint256(OrderType.OFFER)) {
            // If currency owner is not zero address, this is a  created by currency owner
            require(order.taker == msg.sender, "INVALID_TAKER");
        }
    }

    function calculateFillResults(OrderFixed memory order)
        public
        view
        returns (FillResults memory fillResults)
    {
        uint256 currentPrice = getPrice(order);
        fillResults.fee = currentPrice.multiplyDecimal(order.feePercentage);
        fillResults.contractFee = fillResults.fee.multiplyDecimal(
            contractFeePercentage
        );
        fillResults.tradePrice = currentPrice.sub(fillResults.fee);
        fillResults.fee = fillResults.fee.sub(fillResults.contractFee);
    }

    // Update state with results of a fill order.
    function _updateCreatedStates(
        OrderFixed memory order,
        OrderInfo memory orderInfo,
        FillResults memory fillResults
    ) internal {
        // Update order state
        created[orderInfo.orderHash] = true;
        emit Created(
            orderInfo.orderHash,
            fillResults.fee,
            order.feeRecipient,
            fillResults.contractFee,
            msg.sender,
            order.id,
            order.uid,
            order.owner,
            order.assetAddress,
            address(0), //buyer
            order.currencyAddress
        );
    }

    function _updateReverseStates(
        OrderFixed memory order,
        OrderInfo memory orderInfo
    ) internal {
        // Update order state
        created[orderInfo.orderHash] = false;
        emit Reverse(
            orderInfo.orderHash,
            order.id,
            uint256(OrderStatus.REVERSE),
            order.uid
        );
    }

    // Update state with results of a fill order.
    function _updateFilledStates(
        OrderFixed memory order,
        OrderInfo memory orderInfo,
        FillResults memory fillResults
    ) internal {
        require(created[orderInfo.orderHash], "Not created");
        created[orderInfo.orderHash] = false;
        // Update order state
        filled[orderInfo.orderHash] = true;
        emit Fill(
            orderInfo.orderHash,
            fillResults.fee,
            order.feeRecipient,
            fillResults.contractFee,
            msg.sender,
            order.id,
            order.uid,
            order.owner,
            order.assetAddress,
            fillResults.tradePrice,
            order.taker,
            order.currencyAddress
        );
    }

    // Update state with results of a fill order.
    function _updateCreatedStatesFT(
        OrderFixed memory order,
        OrderInfo memory orderInfo,
        FillResults memory fillResults
    ) internal {
        // Update order state
        created[orderInfo.orderHash] = true;
        emit CreatedFT(
            orderInfo.orderHash,
            fillResults.fee,
            order.feeRecipient,
            fillResults.contractFee,
            msg.sender,
            order.id,
            order.uid,
            order.owner,
            order.assetAddress,
            address(0), //buyer
            order.currencyAddress
        );
    }

    function _updateReverseStatesFT(
        OrderFixed memory order,
        OrderInfo memory orderInfo
    ) internal {
        // Update order state
        created[orderInfo.orderHash] = false;
        emit ReverseFT(
            orderInfo.orderHash,
            order.id,
            uint256(OrderStatus.REVERSE),
            order.uid
        );
    }

    // Update state with results of a fill order.
    function _updateFilledStatesFT(
        OrderFixed memory order,
        OrderInfo memory orderInfo,
        FillResults memory fillResults
    ) internal {
        require(created[orderInfo.orderHash], "Not created");
        created[orderInfo.orderHash] = false;
        // Update order state
        filled[orderInfo.orderHash] = true;
        emit FillFT(
            orderInfo.orderHash,
            fillResults.fee,
            order.feeRecipient,
            fillResults.contractFee,
            msg.sender,
            order.id,
            order.uid,
            order.owner,
            order.assetAddress,
            fillResults.tradePrice,
            order.taker,
            order.currencyAddress
        );
    }

    //urgence
    function withdraw(uint256 _balance) external payable onlyOwner {
        msg.sender.transfer(_balance);
    }

    function _settleTrade(
        OrderFixed memory order,
        FillResults memory fillResults
    ) internal {
        if(order.currencyAddress == address(0x0000000000000000000000000000000000000000)){
            address(int160(order.owner)).transfer(fillResults.tradePrice);
            address(int160(order.feeRecipient)).transfer(fillResults.fee);
            address(int160(contractFeeRecipient)).transfer(fillResults.contractFee);
        }
        else{
            // TODO: Enable streaming option for `return policy`
            IERC20(order.currencyAddress).transferFrom(
                order.taker, // buyer
                order.owner, //seller
                fillResults.tradePrice
            );
            IERC20(order.currencyAddress).transferFrom(
                order.taker,
                order.feeRecipient,
                fillResults.fee
            );
            IERC20(order.currencyAddress).transferFrom(
                order.taker,
                contractFeeRecipient,
                fillResults.contractFee
            );
        }

        if (IERC721(order.assetAddress).supportsInterface(0x80ac58cd)) {
            IERC721(order.assetAddress).safeTransferFrom(
                order.owner,
                order.taker,
                order.id,
                ""
            );
        } else if (IERC1155(order.assetAddress).supportsInterface(0xd9b67a26)) {
            IERC1155(order.assetAddress).safeTransferFrom(
                order.owner,
                order.taker,
                order.id,
                1,
                ""
            );
        }
    }

    function _settleTradeFT(
        OrderFixed memory order,
        FillResults memory fillResults
    ) internal {
        if(order.currencyAddress == address(0x0000000000000000000000000000000000000000)){
            address(int160(order.owner)).transfer(fillResults.tradePrice);
            address(int160(order.feeRecipient)).transfer(fillResults.fee);
            address(int160(contractFeeRecipient)).transfer(fillResults.contractFee);
        }
        else{
            // TODO: Enable streaming option for `return policy`
            IERC20(order.currencyAddress).transferFrom(
                order.taker, // buyer
                order.owner, //seller
                fillResults.tradePrice
            );
            IERC20(order.currencyAddress).transferFrom(
                order.taker,
                order.feeRecipient,
                fillResults.fee
            );
            IERC20(order.currencyAddress).transferFrom(
                order.taker,
                contractFeeRecipient,
                fillResults.contractFee
            );
        }

        //从order的uid里取出数量amount的数据，目前是后四位，所以对1万取模
        uint256 _uid =  order.uid;
        uint256 _amount =_uid.mod(100);

        IERC1155(order.assetAddress).safeTransferFrom(
            order.owner,
            order.taker,
            order.id,
            _amount,
            ""
        );
    }

    event Created(
        bytes32 indexed orderHash, // Order's hash
        uint256 fee, // Fee order creator to pay
        address indexed feeRecipient,
        uint256 contractFee, // Fee order creator pay for contract
        address senderAddress, // DEX operator that submitted the order
        uint256 id,
        uint256 uid,
        address indexed owner,
        address assetAddress,
        address taker,
        address currencyAddress
    );

    event Reverse(
        bytes32 indexed orderHash, // Order's hash
        uint256 id, //chy
        uint256 status,
        uint256 uid
    );

    // Fill event is emitted whenever an order is filled.
    event Fill(
        bytes32 indexed orderHash, // Order's hash
        uint256 fee, // Fee order creator to pay
        address indexed feeRecipient,
        uint256 contractFee, // Fee order creator pay for contract
        address senderAddress, // DEX operator that submitted the order
        uint256 id,
        uint256 uid,
        address indexed owner,
        address assetAddress,
        uint256 price,
        address taker,
        address currencyAddress
    );

    event CreatedFT(
        bytes32 indexed orderHash, // Order's hash
        uint256 fee, // Fee order creator to pay
        address indexed feeRecipient,
        uint256 contractFee, // Fee order creator pay for contract
        address senderAddress, // DEX operator that submitted the order
        uint256 id,
        uint256 uid,
        address indexed owner,
        address assetAddress,
        address taker,
        address currencyAddress
    );

    event ReverseFT(
        bytes32 indexed orderHash, // Order's hash
        uint256 id, //chy
        uint256 status,
        uint256 uid
    );

    // Fill event is emitted whenever an order is filled.
    event FillFT(
        bytes32 indexed orderHash, // Order's hash
        uint256 fee, // Fee order creator to pay
        address indexed feeRecipient,
        uint256 contractFee, // Fee order creator pay for contract
        address senderAddress, // DEX operator that submitted the order
        uint256 id,
        uint256 uid,
        address indexed owner,
        address assetAddress,
        uint256 price,
        address taker,
        address currencyAddress
    );

    // Contract fee parameters get updated
    event ContractFeeParamsUpdated(
        address indexed owner,
        uint256 feePercentage,
        address feeRecipient
    );
}
