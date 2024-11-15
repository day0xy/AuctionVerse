// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver, IERC165} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "./AuctionVerse.sol";

contract AuctionVerseFactory {
    address constant atoken;

    //atoken地址部署一次就行了
    constructor(address _atoken) {
        atoken = _atoken;
    }

    address[] public allAuctions;
    mapping(address => address[]) public auctionsBySeller;

    event AuctionCreated(address indexed seller, address auctionAddress);

    function createAuction() external returns (address) {
        AuctionVerse newAuction = new AuctionVerse(IERC1155(atoken));
        allAuctions.push(address(newAuction));
        auctionsBySeller[msg.sender].push(address(newAuction));

        emit AuctionCreated(msg.sender, address(newAuction));
        return address(newAuction);
    }

    function getAllAuctions() external view returns (address[] memory) {
        return allAuctions;
    }

    function getAuctionsBySeller(
        address seller
    ) external view returns (address[] memory) {
        return auctionsBySeller[seller];
    }
}
