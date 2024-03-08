pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { Auctioneer } from  "../Auctioneer.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AuctioneerTest is Test {
    Auctioneer auctioneer;
    IERC20 USD;
    IERC20 GO;
    

    function setUp() public {
      auctioneer = new Auctioneer("hello");
    }

    function test_NumberIs42() public {
        assertEq(testNumber, 42);
    }

    function testFail_Subtract43() public {
        testNumber -= 43;
    }
}