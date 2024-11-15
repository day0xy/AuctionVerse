// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./AuctionVerse.sol";

contract AuctionVerseFactory {
    address[] public allAuctions;
    mapping(address => address[]) public auctionsBySeller;

    event AuctionCreated(address indexed seller, address auctionAddress);

    function createAuction(
        address fractionalizedRealEstateTokenAddress
    ) external returns (address) {
        EnglishAuction newAuction = new EnglishAuction(
            fractionalizedRealEstateTokenAddress
        );
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
