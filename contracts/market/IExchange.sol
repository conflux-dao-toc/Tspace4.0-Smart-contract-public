// SPDX-License-Identifier: MIT
pragma solidity ^0.6.9;


interface IExchange{
    function onSale(address _nft,uint256 _tokenId) view external returns(bool);
}