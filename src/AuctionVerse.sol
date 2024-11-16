// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC1155Receiver, IERC165} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Errors} from "./utils/Errors.sol";
import {IUSDA} from "./interfaces/IUSDA.sol";

contract AuctionVerse is ReentrancyGuard, Errors {
    address public immutable seller;
    address public immutable atoken;
    address public immutable usda;

    struct AuctionDetails {
        uint256 tokenId; //拍卖的tokenId
        uint256 amount; //拍卖的token数量
        uint256 startedBid; //起拍价
        uint256 Increment; //最小加价幅度
        uint256 incrementDuration; //加价幅度持续时间
        uint256 reservePrice; //保留价，如果最高价格没有达到保留价，卖家可以选择不卖
    }

    bool public started;
    uint256 public startTimestamp; //起拍时间
    uint256 public endTimestamp; //结束时间
    uint256 public duration; //持续时间，可以用block.timestamp-
    uint256 public highestBid; //最高出价
    address public highestBidder; //最高出价者
    uint256 public bidDeposit; //起拍价押金为起拍价的3%

    AuctionDetails internal auctionDetails;

    //某个人当前的出价
    mapping(address bidder => uint256 lastestBiddedAmount) public bids;

    event AuctionStarted(
        uint256 indexed tokenId,
        uint256 indexed amount,
        uint256 indexed endTimestamp
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

    //开始拍卖合约
    function startAuction(bytes calldata data) external nonReentrant {
        if (started) revert AuctionVerse_AuctionAlreadyStarted();
        if (msg.sender != seller) revert AuctionVerse_OnlySellerCanCall();

        //将铸造的新的Atoken从卖家转移到拍卖合约地址
        IERC1155(atoken).safeTransferFrom(
            seller,
            address(this),
            auctionDetails.tokenId,
            auctionDetails.amount,
            data
        );

        started = true;
        startTimestamp = block.timestamp;
        endTimestamp = block.timestamp + 7 days;
        highestBid = auctionDetails.startedBid;
        highestBidder = msg.sender;

        emit AuctionStarted(
            auctionDetails.tokenId,
            auctionDetails.amount,
            endTimestamp
        );
    }

    function bid(uint256 amount) external nonReentrant {
        if (!started) revert AuctionVerse_NoAuctionsInProgress();
        if (block.timestamp >= endTimestamp) revert AuctionVerse_AuctionEnded();

        // 检查竞标金额是否大于当前最高竞标
        if (amount <= highestBid) revert AuctionVerse_BidTooLow();

        // 检查竞标金额是否满足最小加价幅度
        if (amount < highestBid + auctionDetails.Increment)
            revert AuctionVerse_BidIncrementTooLow();
        
        // 将USDA从竞标者转移到拍卖合约
        bool success = IUSDA(usda).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) revert AuctionVerse_TransferFailed();

        bids[msg.sender] = amount;

        // 更新最高竞标和竞标者
        highestBid = amount;
        highestBidder = msg.sender;

        emit Bid(msg.sender, amount);
    }

    function endAuction() external nonReentrant {
        if (!started) revert AuctionVerse_NoAuctionsInProgress();
        if (block.timestamp < endTimestamp) revert AuctionVerse_TooEarlyToEnd();

        started = false;

        require(highestBidder != address(0), "Highest bidder not found");
        require(highestBidder != seller, "Seller cannot be the highest bidder");
        // 将拍卖的token转移给最高出价者
        IERC1155(atoken).safeTransferFrom(
            address(this),
            highestBidder,
            auctionDetails.tokenId,
            auctionDetails.amount,
            ""
        );

        // 将最高出价转移给卖家
        IUSDA(usda).transferFrom(address(this), msg.sender, amount);

        emit AuctionEnded(
            auctionDetails.tokenId,
            auctionDetails.amount,
            highestBidder,
            highestBid
        );
    }

    function withdrawBid() external nonReentrant {
        if (started) revert AuctionVerse_AuctionInProgress();
        require(block.timestamp > endTimestamp, "Auction not ended yet");
        if (msg.sender == highestBidder)
            revert AuctionVerse_CannotWithdrawHighestBid();

        uint256 amount = bids[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        delete bids[msg.sender];

        // 退还出价金额
        bool success = IUSDA(usda).transfer(msg.sender, amount);
        if (!success) revert AuctionVerse_TransferFailed();
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
