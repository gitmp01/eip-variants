// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/Spender.sol";

interface IUSDC {
    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

contract SpenderTest is Test {
    IUSDC constant USDC = IUSDC(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant WHALE = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;
    uint256 constant AMOUNT = 100e6; // 100 USDC

    Spender spender;

    function setUp() public {
        vm.createSelectFork("mainnet");
        spender = new Spender();
        deal(address(USDC), WHALE, AMOUNT);
    }

    /// @dev Convenience: runs both steps together.
    function test_approveAndTransferFrom() public {
        vm.startPrank(WHALE);
        uint256 gasBefore = gasleft();
        USDC.approve(address(spender), AMOUNT);
        spender.pull(address(USDC), WHALE, AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("approve() + transferFrom:", gasUsed);
        vm.stopPrank();
    }
}
