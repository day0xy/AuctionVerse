// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC1155Receiver, IERC165} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Errors} from "./utils/Errors.sol";
import {IUSDA} from "./interfaces/IUSDA.sol";

contract AuctionVerse is
    ReentrancyGuard,
    Errors
{
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
    AuctionDetails internal auctionDetails;

    bool public started;
    bool public ended;
    uint256 public startTimestamp; //起拍时间
    uint256 public endTimestamp; //结束时间
    uint256 public duration; //持续时间，可以用block.timestamp-
    uint256 public highestBid; //最高出价
    address public highestBidder; //最高出价者
    uint256 public bidDeposit = (auctionDetails.startedBid * 3) / 100; //起拍价押金为起拍价的3%

    //某个人当前的出价
    mapping(address bidder => uint256 latestBiddedAmount) public bids;
    //记录竞拍者
    mapping(address bidder => bool isDeposit) public isDeposit;
    address[] public bidders;

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

    event AuctionFailed(uint256 indexed tokenId, uint256 amount);

    constructor(address atokenAddress, AuctionDetails memory auctionDetail) {
        seller = msg.sender;
        atoken = atokenAddress;
        auctionDetails = auctionDetail;
    }

    //开始拍卖
    function startAuction(bytes calldata data) external nonReentrant {
        if (started) revert AuctionVerse_AuctionAlreadyStarted();
        if (msg.sender != seller) revert AuctionVerse_OnlySellerCanCall();

        //将铸的新的Atoken从卖家转移到拍卖合约地址
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

    //用USDA出价
    //前端这里同样要限制amount出价的幅度，并且做余额检查
    function bid(uint256 amount) external nonReentrant {
        //如果出价者没有交押金，则交押金
        if (isDeposit[msg.sender] == false) {
            stake();
        }

        require(amount > 0, "Bid amount must be greater than 0");
        //检查出价者余额是否足够
        require(
            IUSDA(usda).balanceOf(msg.sender) >= amount,
            "Insufficient balance"
        );
        if (!started) revert AuctionVerse_NoAuctionsInProgress();
        if (block.timestamp >= endTimestamp) revert AuctionVerse_AuctionEnded();

        // 检查竞标金额是否大于当前最高竞标
        if (amount <= highestBid) revert AuctionVerse_BidTooLow();

        // 检查竞标金额是否满足最小加价幅度
        if (amount < highestBid + auctionDetails.Increment)
            revert AuctionVerse_BidIncrementTooLow();

        // 如果竞标者已经存在于bidders中，不再重复添加
        if (bids[msg.sender] == 0) {
            bidders.push(msg.sender);
        }

        //增加持续时间
        if (block.timestamp + auctionDetails.incrementDuration > endTimestamp) {
            endTimestamp = block.timestamp + auctionDetails.incrementDuration;
        }

        // 更新竞拍者出价
        bids[msg.sender] = amount;
        // 更新最高竞标和竞标者
        highestBid = amount;
        highestBidder = msg.sender;

        emit Bid(msg.sender, amount);
    }

    //结束拍卖
    //最高竞价者把usda转给拍卖合约，拍卖合约把token转给最高竞价者，清空所有竞价者和出价
    function endAuction() external nonReentrant {
        if (!started) revert AuctionVerse_NoAuctionsInProgress();
        if (block.timestamp < endTimestamp) revert AuctionVerse_TooEarlyToEnd();

        started = false;
        ended = true;

        require(highestBidder != address(0), "Highest bidder not found");
        require(highestBidder != seller, "Seller cannot be the highest bidder");

        // 检查合约是否持有足够的token
        require(
            IERC1155(atoken).balanceOf(address(this), auctionDetails.tokenId) >=
                auctionDetails.amount,
            "Insufficient token balance in contract"
        );

        // 把最高出价者的usda token转移给卖家
        require(
            IUSDA(usda).transfer(seller, highestBid),
            "USDA transfer failed"
        );

        // 将拍卖的token转移给最高出价者
        IERC1155(atoken).safeTransferFrom(
            address(this),
            highestBidder,
            auctionDetails.tokenId,
            auctionDetails.amount,
            ""
        );

        emit AuctionEnded(
            auctionDetails.tokenId,
            auctionDetails.amount,
            highestBidder,
            highestBid
        );

        for (uint i = 0; i < bidders.length; i++) {
            delete bids[bidders[i]];
        }
        delete bidders;
    }

    // 新增流拍函数
    function failAuction() external nonReentrant {
        if (!started) revert AuctionVerse_NoAuctionsInProgress();

        if (block.timestamp < endTimestamp) revert AuctionVerse_TooEarlyToEnd();

        // 检查是否达到保留价
        if (highestBid < auctionDetails.reservePrice) {
            started = false;

            // 将拍卖的token退还给卖家
            IERC1155(atoken).safeTransferFrom(
                address(this),
                seller,
                auctionDetails.tokenId,
                auctionDetails.amount,
                ""
            );

            emit AuctionFailed(auctionDetails.tokenId, auctionDetails.amount);

            for (uint i = 0; i < bidders.length; i++) {
                delete bids[bidders[i]];
            }
            delete bidders;
        } else {
            revert AuctionVerse_ReservePriceMet();
        }
    }

    function onERC1155Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*id*/,
        uint256 /*value*/,
        bytes calldata /*data*/
    ) external view returns (bytes4) {
        if (msg.sender != address(atoken)) {
            revert OnlyATokenSupported();
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
            revert OnlyATokenSupported();
        }

        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    //approve由前端进行
    function stake() internal {
        require(isDeposit[msg.sender] == false, "Already staked");

        // 从出价者账户转移USDA到合约,锁定起来
        require(
            IUSDA(usda).transferFrom(msg.sender, address(this), bidDeposit),
            "USDA transfer failed"
        );

        isDeposit[msg.sender] = true;
    }

    function getSeller() external view returns (address) {
        return seller;
    }

    // // Chainlink Keepers 需要实现的接口
    // function checkUpkeep(
    //     bytes calldata /*checkData*/
    // )
    //     external
    //     view
    //     override
    //     returns (bool upkeepNeeded, bytes memory /*performData*/)
    // {
    //     upkeepNeeded =
    //         started &&
    //         block.timestamp >= endTimestamp &&
    //         highestBid < auctionDetails.reservePrice;
    // }

    // function performUpkeep(bytes calldata /*performData*/) external override {
    //     if (
    //         started &&
    //         block.timestamp >= endTimestamp &&
    //         highestBid < auctionDetails.reservePrice
    //     ) {
    //         failAuction();
    //     }
    // }
}
