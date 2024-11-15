// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "./utils/Errors.sol";

contract AuctionVerse is ReentrancyGuard {
    address internal immutable seller;
    address internal immutable atoken;

    bool internal started;
    uint256 internal startTimestamp; //起拍时间
    uint48 internal endTimestamp; //结束时间
    uint256 internal startedBid; //起拍价
    uint256 internal bidDeposit; //起拍价押金
    uint256 internal minimumIncrement; //最小加价幅度
    uint256 internal incrementDuration; //加价幅度持续时间
    uint256 internal duration; //持续时间，可以用block.timestamp-
    address internal highestBidder; //最高出价者
    uint256 internal highestBid; //最高出价
    uint256 internal reservePrice; //保留价，如果最高价格没有达到保留价，卖家可以选择不卖
    uint256 internal tokenIdOnAuction;

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

    constructor(address atokenAddress) {
        seller = msg.sender;
        Atoken = atokenAddress;
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
            i_seller,
            address(this),
            tokenId,
            amount,
            data
        );

        s_started = true;
        s_endTimestamp = SafeCast.toUint48(block.timestamp + 7 days);
        s_tokenIdOnAuction = tokenId;
        s_fractionalizedAmountOnAuction = amount;
        s_highestBidder = msg.sender;
        s_highestBid = startingBid;

        emit AuctionStarted(tokenId, amount, s_endTimestamp);
    }

    function getTokenIdOnAuction() external view returns (uint256) {
        return s_tokenIdOnAuction;
    }

    function bid() external payable nonReentrant {
        if (!s_started) revert AuctionVerse_NoAuctionsInProgress();
        if (block.timestamp >= s_endTimestamp)
            revert AuctionVerse_AuctionEnded();
        if (msg.value <= s_highestBid) revert AuctionVerse_BidNotHighEnough();

        s_highestBidder = msg.sender;
        s_highestBid = msg.value;
        s_bids[msg.sender] += msg.value;

        emit Bid(msg.sender, msg.value);
    }

    function withdrawBid() external nonReentrant {
        if (msg.sender == s_highestBidder)
            revert AuctionVerse_CannotWithdrawHighestBid();

        uint256 amount = s_bids[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        delete s_bids[msg.sender];

        (bool sent, ) = msg.sender.call{value: amount}("");

        if (!sent) revert FailedToWithdrawBid(msg.sender, amount);
    }

    function endAuction() external nonReentrant {
        if (!s_started) revert AuctionVerse_NoAuctionsInProgress();
        if (block.timestamp < s_endTimestamp)
            revert AuctionVerse_TooEarlyToEnd();

        s_started = false;

        IERC1155(i_fractionalizedRealEstateToken).safeTransferFrom(
            address(this),
            s_highestBidder,
            s_tokenIdOnAuction,
            s_fractionalizedAmountOnAuction,
            ""
        );

        (bool sent, ) = i_seller.call{value: s_highestBid}("");
        if (!sent) revert FailedToSendEth(i_seller, s_highestBid);

        emit AuctionEnded(
            s_tokenIdOnAuction,
            s_fractionalizedAmountOnAuction,
            s_highestBidder,
            s_highestBid
        );
    }

    function onERC1155Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*id*/,
        uint256 /*value*/,
        bytes calldata /*data*/
    ) external view returns (bytes4) {
        if (msg.sender != address(i_fractionalizedRealEstateToken)) {
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
        if (msg.sender != address(i_fractionalizedRealEstateToken)) {
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
}
