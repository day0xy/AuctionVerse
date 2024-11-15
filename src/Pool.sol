// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IUSDA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Pool {
    IERC20 public usdc;
    IUSDA public usda;

    constructor(address _usdc, address _usda) {
        usdc = IERC20(_usdc);
        usda = IUSDA(_usda);
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");

        // Transfer USDC from user to this contract
        bool success = usdc.transferFrom(msg.sender, address(this), amount);
        require(success, "USDC transfer failed");

        // Mint equivalent amount of USDA to the user
        usda.mint(amount);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");

        // Redeem USDA from the user
        usda.redeem(amount);

        // Transfer equivalent amount of USDC from this contract to the user
        bool success = usdc.transfer(msg.sender, amount);
        require(success, "USDC transfer failed");
    }
}
