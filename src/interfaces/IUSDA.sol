// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDA is ERC20 {
    IERC20 public usdc;

    constructor(address usdcAddress) ERC20("USD Alpha", "USDA") {
        usdc = IERC20(usdcAddress);
    }

    function mint(uint256 usdcAmount) external {
        require(usdc.transferFrom(msg.sender, address(this), usdcAmount), "USDC transfer failed");
        _mint(msg.sender, usdcAmount);
    }

    function redeem(uint256 usdaAmount) external {
        require(balanceOf(msg.sender) >= usdaAmount, "Insufficient USDA balance");
        _burn(msg.sender, usdaAmount);
        require(usdc.transfer(msg.sender, usdaAmount), "USDC transfer failed");
    }
}
