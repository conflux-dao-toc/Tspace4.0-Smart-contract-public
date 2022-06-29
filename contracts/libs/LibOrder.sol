// SPDX-License-Identifier: MIT

pragma solidity ^0.6.9;

import "./LibEIP712.sol";

contract LibOrder is LibEIP712 {
    string private constant ORDER_TYPE =
        "Order(address owner,address taker,address operator,uint256 orderType,uint256 uid,uint256 startPrice,uint256 endTime,uint256 salt,address assetAddress,uint256 id,address currencyAddress,address feeRecipient,uint256 feePercentage)";
    bytes32 private constant ORDER_TYPEHASH =
        keccak256(abi.encodePacked(ORDER_TYPE));

    // A valid order remains fillable until it is expired, fully filled, or cancelled.
    // An order's state is unaffected by external factors, like account balances.
    enum OrderStatus {
        INVALID, // Default value
        INVALID_OPERATOR, // Order orderType is invalid
        FILLABLE, // Order is fillable
        EXPIRED, // Order has already expired
        FILLED, // Order is fully filled
        CANCELLED, // Order is cancelled
        CREATED, // order created
        REVERSE// order reverse
    }

    enum OrderType {CREATE, SALE, OFFER, INVALID_TYPE}
    //enum OrderType {SALE, OFFER, INVALID_TYPE}

    // solhint-disable max-line-length
    struct Order {
        address owner;
        address taker;
        address operator;
        uint256 orderType;
        uint256 uid; // external id ,replace of old "amount",but last 4 positions for amount. 1208更新：针对非同质化，存的就是外部数据；针对同质化，后四位是amount, 前面是外部数据。使用时候注意转换。
        uint256 startPrice;
        uint256 endTime;
        uint256 salt; // Arbitrary number to facilitate uniqueness of the order's hash.
        address assetAddress;
        uint256 id;
        address currencyAddress;
        address feeRecipient;
        uint256 feePercentage;
    }
    // solhint-enable max-line-length
    
     struct OrderFixed {
        address owner;
        address taker;
        address operator;
        uint256 orderType;
        uint256 uid; //external id ,replace of old "amount",but last 4 positions for amount. 后四位是amount,前面是外部数据。使用时候注意转换
        uint256 startPrice;
        uint256 salt; // Arbitrary number to facilitate uniqueness of the order's hash.
        address assetAddress;
        uint256 id; //nft id
        address currencyAddress;
        address feeRecipient;
        uint256 feePercentage;
    }

    struct OrderInfo {
        OrderStatus orderStatus; // Status that describes order's validity and fillability.
        bytes32 orderHash; // EIP712 hash of the order (see LibOrder.getOrderHash).
        bool filled;
    }

    // Calculates Keccak-256 hash of the order.
    function getOrderHash(Order memory order)
        internal
        view
        returns (bytes32 orderHash)
    {
        orderHash = hashEIP712Message(hashOrder(order));
        return orderHash;
    }
    
    function getOrderFixedHash(OrderFixed memory order)
        internal
        view
        returns (bytes32 orderHash)
    {
        orderHash = hashEIP712Message(hashOrderFixed(order));
        return orderHash;
    }

    // Calculates EIP712 hash of the order.
    function hashOrder(Order memory order)
        internal
        pure
        returns (bytes32 result)
    {
        return
            keccak256(
                abi.encode(
                    ORDER_TYPEHASH,
                    order.owner,
                    order.taker,
                    order.operator,
                    order.orderType,
                    order.uid,
                    order.startPrice,
                    order.endTime,
                    order.salt,
                    order.assetAddress,
                    order.id,
                    order.currencyAddress,
                    order.feeRecipient,
                    order.feePercentage
                )
            );
    }
    
    function hashOrderFixed(OrderFixed memory order)
        internal
        pure
        returns (bytes32 result)
    {
        return
            keccak256(
                abi.encode(
                    ORDER_TYPEHASH,
                    order.owner,
                    order.taker,
                    order.operator,
                    order.orderType,
                    order.uid,
                    order.startPrice,
                    order.salt,
                    order.assetAddress,
                    order.id,
                    order.currencyAddress,
                    order.feeRecipient,
                    order.feePercentage
                )
            );
    }
}
