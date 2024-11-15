// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AToken is ERC1155, Ownable {
    uint256 public _currentID;

    constructor()
        ERC1155("https://api.example.com/metadata/{id}.json")
        Ownable(msg.sender)
    {
        _currentID = 0;
    }

    // 仅限合约所有者调用
    function mint(address to, uint256 amount) external onlyOwner {
        _currentID += 1;

        _mint(to, _currentID, amount, "");
    }

    function getCurrentId() public view returns (uint256) {
        return _currentID;
    }
}
