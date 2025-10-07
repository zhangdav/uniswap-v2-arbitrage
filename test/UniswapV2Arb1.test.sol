// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWETH} from "../src/IWEH.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {
    DAI,
    WETH,
    UNISWAP_V2_ROUTER_02,
    SUSHISWAP_V2_ROUTER_02,
    UNISWAP_V2_PAIR_DAI_WETH,
    UNISWAP_V2_PAIR_DAI_MKR
} from "../src/Constants.sol";
import {UniswapV2Arbitrage} from "../src/UniswapV2Arbitrage.sol";

contract UniswapV2Arb1Test is Test {
    IUniswapV2Router02 private constant uni_router = IUniswapV2Router02(UNISWAP_V2_ROUTER_02);
    IUniswapV2Router02 private constant sushiswap_router = IUniswapV2Router02(SUSHISWAP_V2_ROUTER_02);
    IERC20 private constant dai = IERC20(DAI);
    IWETH private constant weth = IWETH(WETH);
    address constant user = address(11);

    UniswapV2Arbitrage private arb;

    function setUp() public {
        arb = new UniswapV2Arbitrage();

        // Setup - WETH cheaper on Uniswap than Sushiswap
        deal(address(this), 100 * 1e18);

        weth.deposit{value: 100 * 1e18}();
        weth.approve(address(uni_router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;

        uni_router.swapExactTokensForTokens({
            amountIn: 100 * 1e18,
            amountOutMin: 1,
            path: path,
            to: user,
            deadline: block.timestamp
        });

        // Setup - user has DAI, approves arb to spend DAI
        deal(DAI, user, 10000 * 1e18);
        vm.prank(user);
        dai.approve(address(arb), type(uint256).max);
    }

    function test_swap() public {
        uint256 bal0 = dai.balanceOf(user);
        vm.prank(user);
        arb.swap(
            UniswapV2Arbitrage.SwapParams({
                router0: UNISWAP_V2_ROUTER_02,
                router1: SUSHISWAP_V2_ROUTER_02,
                tokenIn: DAI,
                tokenOut: WETH,
                amountIn: 10000 * 1e18,
                minProfit: 1
            })
        );

        uint256 bal1 = dai.balanceOf(user);

        assertGe(bal1, bal0, "no profit");
        assertEq(dai.balanceOf(address(arb)), 0, "DAI balance of arb != 0");
        console2.log("profit", bal1 - bal0);
    }

    // Pool liquidity is too low, this test will fail
    function test_flashSwap() public {
        uint256 bal0 = dai.balanceOf(user);
        vm.prank(user);
        arb.flashSwap(
            UNISWAP_V2_PAIR_DAI_MKR,
            true,
            UniswapV2Arbitrage.SwapParams({
                router0: UNISWAP_V2_ROUTER_02,
                router1: SUSHISWAP_V2_ROUTER_02,
                tokenIn: DAI,
                tokenOut: WETH,
                amountIn: 10000 * 1e18,
                minProfit: 1
            })
        );
        uint256 bal1 = dai.balanceOf(user);

        assertGe(bal1, bal0, "no profit");
        assertEq(dai.balanceOf(address(arb)), 0, "DAI balance of arb != 0");
        console2.log("profit", bal1 - bal0);
    }
}