// SPDX-License-Identifier: MIT

pragma solidity ^0.6.9;
pragma experimental ABIEncoderV2;

contract LibSignatureValidator {
    function readBytes32(bytes memory b, uint256 index) internal pure returns (bytes32 result) {
        require (b.length >= index + 32, "Wrong length");

        // Arrays are prefixed by a 256 bit length parameter
        index += 32;

        // Read the bytes64 from array memory
        assembly {
            result := mload(add(b, index))
        }
        return result;
    }
    
    function isValidSignature(
        bytes32 hash,
        address signerAddress,
        bytes memory signature
    )
        public
        pure
        returns (bool isValid)
    {
        require(signerAddress != address(0), "Wrong signer address");
        require(signature.length == 65, "Wrong length of signature");
        uint8 sigV = uint8(signature[64]);
        require(sigV == 27 || sigV == 28, "Wrong V");
        bytes32 sigR = readBytes32(signature, 0);
        bytes32 sigS = readBytes32(signature, 32);

        return signerAddress == ecrecover(hash, sigV, sigR, sigS);
    }
}