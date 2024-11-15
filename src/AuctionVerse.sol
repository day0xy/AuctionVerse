// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC1155Receiver, IERC165} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {Errors} from "./utils/Errors.sol";

contract AuctionVerse is ReentrancyGuard, Errors {
    address internal immutable seller;
    address internal immutable atoken;

    struct AuctionDetails {
        uint256 startedBid; //起拍价
        uint256 Increment; //最小加价幅度
        uint256 incrementDuration; //加价幅度持续时间
        uint256 reservePrice; //保留价，如果最高价格没有达到保留价，卖家可以选择不卖
        uint256 tokenIdOnAuction;
        uint256 fractionalizedAmountOnAuction;
    }

    bool started;
    uint256 startTimestamp; //起拍时间
    uint48 endTimestamp; //结束时间
    uint256 duration; //持续时间，可以用block.timestamp-
    uint256 highestBid; //最高出价
    address highestBidder; //最高出价者
    uint256 bidDeposit; //起拍价押金为起拍价的3%

    AuctionDetails internal auctionDetails;

    mapping(address bidder => uint256 totalBiddedEth) internal bids;

    event AuctionStarted(
        uint256 indexed tokenId,
        uint256 indexed amount,
        uint48 indexed endTimestamp
    );

    event Bid(address indexed bidder, uint256 indexed amount);
    event AuctionEnded(
        uint256 indexed tokenId,
        uint256 amount,
        address indexed winner,
        uint256 indexed winningBid
    );

    constructor(address atokenAddress, AuctionDetails memory auctionDetail) {
        seller = msg.sender;
        atoken = atokenAddress;
        auctionDetails = auctionDetail;
    }

    function startAuction(
        uint256 tokenId,
        uint256 amount,
        bytes calldata data,
        uint256 startingBid
    ) external nonReentrant {
        if (started) revert AuctionVerse_AuctionAlreadyStarted();
        if (msg.sender != seller) revert AuctionVerse_OnlySellerCanCall();

        IERC1155(atoken).safeTransferFrom(
            seller,
            address(this),
            tokenId,
            amount,
            data
        );

        started = true;
        endTimestamp = SafeCast.toUint48(block.timestamp + 7 days);
        tokenIdOnAuction = tokenId;
        fractionalizedAmountOnAuction = amount;
        highestBidder = msg.sender;
        highestBid = startingBid;

        emit AuctionStarted(tokenId, amount, endTimestamp);
    }

    function getTokenIdOnAuction() external view returns (uint256) {
        return tokenIdOnAuction;
    }

    function bid() external payable nonReentrant {
        if (!started) revert AuctionVerse_NoAuctionsInProgress();
        if (block.timestamp >= endTimestamp) revert AuctionVerse_AuctionEnded();
        if (msg.value <= highestBid) revert AuctionVerse_BidNotHighEnough();

        highestBidder = msg.sender;
        highestBid = msg.value;
        bids[msg.sender] += msg.value;

        emit Bid(msg.sender, msg.value);
    }

    function withdrawBid() external nonReentrant {
        if (msg.sender == highestBidder)
            revert AuctionVerse_CannotWithdrawHighestBid();

        uint256 amount = bids[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        delete bids[msg.sender];

        (bool sent, ) = msg.sender.call{value: amount}("");

        if (!sent) revert FailedToWithdrawBid(msg.sender, amount);
    }

    function endAuction() external nonReentrant {
        if (!started) revert AuctionVerse_NoAuctionsInProgress();
        if (block.timestamp < endTimestamp) revert AuctionVerse_TooEarlyToEnd();

        started = false;

        IERC1155(atoken).safeTransferFrom(
            address(this),
            highestBidder,
            tokenIdOnAuction,
            fractionalizedAmountOnAuction,
            ""
        );

        (bool sent, ) = seller.call{value: highestBid}("");
        if (!sent) revert FailedToSendEth(seller, highestBid);

        emit AuctionEnded(
            tokenIdOnAuction,
            fractionalizedAmountOnAuction,
            highestBidder,
            highestBid
        );
    }

    function onERC1155Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*id*/,
        uint256 /*value*/,
        bytes calldata /*data*/
    ) external view returns (bytes4) {
        if (msg.sender != address(atoken)) {
            revert OnlyRealEstateTokenSupported();
        }

        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address /*operator*/,
        address /*from*/,
        uint256[] calldata /*ids*/,
        uint256[] calldata /*values*/,
        bytes calldata /*data*/
    ) external view returns (bytes4) {
        if (msg.sender != address(atoken)) {
            revert OnlyRealEstateTokenSupported();
        }

        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC165) returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }


    function getSeller() external view returns (address) {
        return seller;
    }
}
