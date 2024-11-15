// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract AToken is ERC1155 {
    uint256 public _currentID;

    constructor() ERC1155("https://api.example.com/metadata/{id}.json") {
        _currentID = 0;
    }

    //mint调用权限问题
    function mint(address to, uint256 amount) external {
        _currentID += 1;

        _mint(to, _currentID, amount, "");
    }

    function getCurrentId() public view returns (uint256) {
        return _currentID;
    }
}
