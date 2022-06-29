// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.7.0;
//import "./owner/Operator.sol";

interface IUniswapV2Pair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}
// computes square roots using the babylonian method
// https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method
library Babylonian {
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
        // else z = 0
    }
}

library FixedPoint {
    // range: [0, 2**112 - 1]
    // resolution: 1 / 2**112
    struct uq112x112 {
        uint224 _x;
    }

    // range: [0, 2**144 - 1]
    // resolution: 1 / 2**112
    struct uq144x112 {
        uint _x;
    }

    uint8 private constant RESOLUTION = 112;
    uint private constant Q112 = uint(1) << RESOLUTION;
    uint private constant Q224 = Q112 << RESOLUTION;

    // encode a uint112 as a UQ112x112
    function encode(uint112 x) internal pure returns (uq112x112 memory) {
        return uq112x112(uint224(x) << RESOLUTION);
    }

    // encodes a uint144 as a UQ144x112
    function encode144(uint144 x) internal pure returns (uq144x112 memory) {
        return uq144x112(uint256(x) << RESOLUTION);
    }

    // divide a UQ112x112 by a uint112, returning a UQ112x112
    function div(uq112x112 memory self, uint112 x) internal pure returns (uq112x112 memory) {
        require(x != 0, 'FixedPoint: DIV_BY_ZERO');
        return uq112x112(self._x / uint224(x));
    }

    // multiply a UQ112x112 by a uint, returning a UQ144x112
    // reverts on overflow
    function mul(uq112x112 memory self, uint y) internal pure returns (uq144x112 memory) {
        uint z;
        require(y == 0 || (z = uint(self._x) * y) / y == uint(self._x), "FixedPoint: MULTIPLICATION_OVERFLOW");
        return uq144x112(z);
    }

    // returns a UQ112x112 which represents the ratio of the numerator to the denominator
    // equivalent to encode(numerator).div(denominator)
    function fraction(uint112 numerator, uint112 denominator) internal pure returns (uq112x112 memory) {
        require(denominator > 0, "FixedPoint: DIV_BY_ZERO");
        return uq112x112((uint224(numerator) << RESOLUTION) / denominator);
    }

    // decode a UQ112x112 into a uint112 by truncating after the radix point
    function decode(uq112x112 memory self) internal pure returns (uint112) {
        return uint112(self._x >> RESOLUTION);
    }

    // decode a UQ144x112 into a uint144 by truncating after the radix point
    function decode144(uq144x112 memory self) internal pure returns (uint144) {
        return uint144(self._x >> RESOLUTION);
    }

    // take the reciprocal of a UQ112x112
    function reciprocal(uq112x112 memory self) internal pure returns (uq112x112 memory) {
        require(self._x != 0, 'FixedPoint: ZERO_RECIPROCAL');
        return uq112x112(uint224(Q224 / self._x));
    }

    // square root of a UQ112x112
    function sqrt(uq112x112 memory self) internal pure returns (uq112x112 memory) {
        return uq112x112(uint224(Babylonian.sqrt(uint256(self._x)) << 56));
    }
}



library UniswapV2OracleLibrary {
    using FixedPoint for *;

    // helper function that returns the current block timestamp within the range of uint32, i.e. [0, 2**32 - 1]
    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2 ** 32);
    }

    // produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
    function currentCumulativePrices(
        address pair
    ) internal view returns (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) {
        blockTimestamp = currentBlockTimestamp();
        price0Cumulative = IUniswapV2Pair(pair).price0CumulativeLast();
        price1Cumulative = IUniswapV2Pair(pair).price1CumulativeLast();

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
        if (blockTimestampLast != blockTimestamp) {
            // subtraction overflow is desired
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;
            // addition overflow is desired
            // counterfactual
            price0Cumulative += uint(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
            // counterfactual
            price1Cumulative += uint(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsed;
        }
    }
}


contract SponsorWhitelistControl {
  /*** Query Functions ***/
  /**
    * @dev get gas sponsor address of specific contract
    * @param contractAddr The address of the sponsored contract
    */
  function getSponsorForGas(address contractAddr) public view returns (address) {}

  /**
    * @dev get current Sponsored Balance for gas
    * @param contractAddr The address of the sponsored contract
    */
  function getSponsoredBalanceForGas(address contractAddr) public view returns (uint) {}

  /**
    * @dev get current Sponsored Gas fee upper bound
    * @param contractAddr The address of the sponsored contract
    */
  function getSponsoredGasFeeUpperBound(address contractAddr) public view returns (uint) {}

  /**
    * @dev get collateral sponsor address
    * @param contractAddr The address of the sponsored contract
    */
  function getSponsorForCollateral(address contractAddr) public view returns (address) {}

  /**
    * @dev get current Sponsored Balance for collateral
    * @param contractAddr The address of the sponsored contract
    */
  function getSponsoredBalanceForCollateral(address contractAddr) public view returns (uint) {}

  /**
    * @dev check if a user is in a contract's whitelist
    * @param contractAddr The address of the sponsored contract
    * @param user The address of contract user
    */
  function isWhitelisted(address contractAddr, address user) public view returns (bool) {}

  /**
    * @dev check if all users are in a contract's whitelist
    * @param contractAddr The address of the sponsored contract
    */
  function isAllWhitelisted(address contractAddr) public view returns (bool) {}

  /*** for contract admin only **/
  /**
    * @dev contract admin add user to whitelist
    * @param contractAddr The address of the sponsored contract
    * @param addresses The user address array
    */
  function addPrivilegeByAdmin(address contractAddr, address[] memory addresses) public {}

  /**
    * @dev contract admin remove user from whitelist
    * @param contractAddr The address of the sponsored contract
    * @param addresses The user address array
    */
  function removePrivilegeByAdmin(address contractAddr, address[] memory addresses) public {}

  // ------------------------------------------------------------------------
  // Someone will sponsor the gas cost for contract `contractAddr` with an
  // `upper_bound` for a single transaction.
  // ------------------------------------------------------------------------
  function setSponsorForGas(address contractAddr, uint upperBound) public payable {}

  // ------------------------------------------------------------------------
  // Someone will sponsor the storage collateral for contract `contractAddr`.
  // ------------------------------------------------------------------------
  function setSponsorForCollateral(address contractAddr) public payable {}

  // ------------------------------------------------------------------------
  // Add commission privilege for address `user` to some contract.
  // ------------------------------------------------------------------------
  function addPrivilege(address[] memory) public {}

  // ------------------------------------------------------------------------
  // Remove commission privilege for address `user` from some contract.
  // ------------------------------------------------------------------------
  function removePrivilege(address[] memory) public {}
}

contract PriceOracle2 {

    address payable public owner;

    SponsorWhitelistControl constant private SPONSOR = SponsorWhitelistControl(address(0x0888000000000000000000000000000000000001));

    modifier onlyOwner() {
        require(
            owner == msg.sender,
            'owner: caller is not the owner'
        );
        _;
    }


    constructor() public {
        owner = msg.sender;

        addPrivilege(address(0x0));
    }

    function addPrivilege(address account) public payable {
        address[] memory a = new address[](1);
        a[0] = account;
        SPONSOR.addPrivilege(a);
    }

    function removePrivilege(address account) public payable {
        address[] memory a = new address[](1);
        a[0] = account;
        SPONSOR.removePrivilege(a);
    }

    function changeOwner(address payable _newOwner) public {
        require(owner == msg.sender);
        owner = _newOwner;
    }


    /// 测试网
    // function UsdtToCfxPrice(uint256 cUsdt) public view returns (uint256) { 
        
    //     (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(address(0x8a3cc1FdD1ABE2d803E774AA463e13431878c200)).getReserves();
        
    //     return cUsdt * reserve1 / reserve0; 
    // }
    

    //目前我们采用6位精度，即传入参数时候，乘以10的六次方，得到返回值除以10的六次方
    //测试网
    function tokenToUsdtPrice(uint256 _amount, address _tokenAddress) public view returns (uint256) { 
        //wcfx
        if(_tokenAddress == address(0x8EECAc87012C8e25d1A5c27694Ae3DdaF2B6572F)){
            (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(address(0x8a3cc1FdD1ABE2d803E774AA463e13431878c200)).getReserves();
            return _amount * reserve0 / reserve1; 
        }else{
            return _amount;
        }
    }
    //目前我们采用6位精度，即传入参数时候，乘以10的六次方，得到返回值除以10的六次方
    //正式网
    function tokenToUsdtPrice(uint256 _amount, address _tokenAddress) public view returns (uint256) { 
        //wcfx
        if(_tokenAddress == address(0x8d7DF9316FAa0586e175B5e6D03c6bda76E3d950)){
            (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(address(0x8D545118D91C027C805c552f63A5c00a20aE6Aca)).getReserves(); 
            return _amount * reserve0 / reserve1; 
        }
        //FC
        else if(_tokenAddress == address(0x8e2F2E68eB75bB8B18caAFE9607242D4748f8D98)){
            (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(address(0x8f05979730aFE9219b5B32C0b355b7247f9df259)).getReserves(); 
            return _amount * reserve0 / reserve1; 
        }
        //moon
        else if(_tokenAddress == address(0x8e28460074f2FF545053E502E774dDdC97125110)){
           (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(address(0x8F7B6A79d0B7e080e6381b03b7D396C56114b5A4)).getReserves(); 
            return _amount * reserve0 / reserve1; 
        }
        //eth
        else if(_tokenAddress == address(0x86D2Fb177efF4bE03A342951269096265b98AC46)){
           (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(address(0x8689b0c36D65F0CBed051dD36A649D3C68D67B6f)).getReserves(); 
            return _amount * reserve1 / reserve0; 
        }else{
            return _amount;
        }
       
    }

    
   

    //moonswap - YAO-CFX
    //输入YAO amount, 获取对应的usdt amount，通过cfx倒一手
    function YAOToUsdtPrice(uint256 YAO) public view returns (uint256) { 
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(address(0x8D545118D91C027C805c552f63A5c00a20aE6Aca)).getReserves(); 
        (uint112 reserve2, uint112 reserve3, uint32 blockTimestampLast1) = IUniswapV2Pair(address(0x8c306998309507ad7f8cfeA81B8A9be2aCfE0a00)).getReserves(); 
        return YAO * reserve3 / reserve2 * reserve0 / reserve1 ;
    }

    //moonswap - cUSDT-cMOON
    //输入moon amount, 获取对应的usdt amount
    function MoonToUsdtPrice(uint256 cMoon) public view returns (uint256) { 
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(address(0x8F7B6A79d0B7e080e6381b03b7D396C56114b5A4)).getReserves(); 
        return cMoon * reserve0 / reserve1; 
    }

    //moonswap - cETH - cUSDT
    //输入cETH amount, 获取对应的usdt amount
    function EthToUsdtPrice(uint256 cETH) public view returns (uint256) { 
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(address(0x8689b0c36D65F0CBed051dD36A649D3C68D67B6f)).getReserves(); 
        return cETH * reserve1 / reserve0; 
    }

    //moonswap - TREA - cUSDT
    //输入TREA amount, 获取对应的usdt amount
    function TreaToUsdtPrice(uint256 Trea) public view returns (uint256) { 
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(address(0x8689b0c36D65F0CBed051dD36A649D3C68D67B6f)).getReserves(); 
        return Trea * reserve1 / reserve0; 
    }

    //moonswap - cUSDT-cFlux
    //输入cFlux amount, 获取对应的usdt amount
    function FluxToUsdtPrice(uint256 cFlux) public view returns (uint256) { 
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(address(0x805E1F3E0B9500CC00a99915aE831d1D927737Ae)).getReserves(); 
        return cFlux * reserve0 / reserve1; 
    }
}
