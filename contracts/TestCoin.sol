pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
// import "./SponsorWhitelistControl.sol";
import "./owner/Operator.sol";

contract TestCoin is ERC777, Operator{

    // address public minter;

    // mapping(address=>bool) mainMinter;

    // SponsorWhitelistControl public constant SPONSOR = SponsorWhitelistControl(
    //     address(0x0888000000000000000000000000000000000001)
    // );

    constructor()
        ERC777("UU Token", "UUU", new address[](0))
        public
    {
        _mint(msg.sender, 1000000000e18, "", "");
        // register all users as sponsees
        // address[] memory users = new address[](1);
        // users[0] = address(0);
        // SPONSOR.addPrivilege(users);
    }

    function addTokens(address _to, uint256 _value) external onlyMiner(){
        _mint(_to, _value, "", "");
    }
}
