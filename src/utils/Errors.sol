// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Errors {
    error AuctionVerse_OnlySellerCanCall();
    error AuctionVerse_AuctionAlreadyStarted();
    error OnlyRealEstateTokenSupported();
    error AuctionVerse_NoAuctionsInProgress();
    error AuctionVerse_AuctionEnded();
    error AuctionVerse_BidTooLow();
    error AuctionVerse_BidIncrementTooLow();
    error AuctionVerse_TransferFailed();
    error AuctionVerse_CannotWithdrawHighestBid();
    error AuctionVerse_TooEarlyToEnd();
    error FailedToWithdrawBid(address bidder, uint256 amount);
    error NothingToWithdraw();
    error FailedToSendEth(address recipient, uint256 amount);
}
