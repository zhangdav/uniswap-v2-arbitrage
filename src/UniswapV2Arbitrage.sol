// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract UniswapV2Arbitrage {
    using SafeERC20 for IERC20;

    struct SwapParams {
        // Router to execute first swap - tokenIn for tokenOut
        address router0;
        // Router to execute second swap - tokenOut for tokenIn
        address router1;
        // Token in of first swap
        address tokenIn;
        // Token out of first swap
        address tokenOut;
        // Amount in for the first swap
        uint256 amountIn;
        // Revert the arbitrage if profit is less than minimum profit
        uint256 minProfit;
    }

    function _swap(SwapParams memory params) private returns (uint256 amountOut) {
        // Swap on router0 (tokenIn -> tokenOut)
        IERC20(params.tokenIn).approve(params.router0, params.amountIn);

        address[] memory path = new address[](2);
        path[0] = params.tokenIn;
        path[1] = params.tokenOut;

        uint256 [] memory amounts =IUniswapV2Router02(params.router0).swapExactTokensForTokens({
            amountIn: params.amountIn,
            // MEV risk
            amountOutMin: 0,
            path: path,
            to: address(this),
            deadline: block.timestamp
        });

        // Swap on router1 (tokenOut -> tokenIn)
        IERC20(params.tokenOut).approve(params.router1, amounts[1]);

        path[0] = params.tokenOut;
        path[1] = params.tokenIn;

        amounts =IUniswapV2Router02(params.router1).swapExactTokensForTokens({
            amountIn: amounts[1],
            amountOutMin: params.amountIn,
            path: path,
            to: address(this),
            deadline: block.timestamp
        });

        amountOut = amounts[1];
    }

    // Execute an arbitrage between router0 and router1
    // Pull tokenIn from msg.msg.sender
    // Send amountIn + profit back to msg.sender
    function swap(SwapParams calldata params) external {
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        uint amountOut = _swap(params);

        require(amountOut - params.amountIn >= params.minProfit, "proft < min");
        IERC20(params.tokenIn).transfer(msg.sender, amountOut);
    }

    // Execute an arbitrage between router0 and router1 using flash swap
    // Borrow tokenIn with flash swap from pair
    // Send profit back to msg.sender
    function flashSwap(address pair, bool isToken0, SwapParams memory params) external {
        bytes memory data = abi.encode(msg.sender, pair, params);

        IUniswapV2Pair(pair).swap({
            amount0Out: isToken0 ? params.amountIn : 0,
            amount1Out: isToken0 ? 0 : params.amountIn,
            to: address(this),
            data: data
        });
    }

    function uniswapV2Call(
        address sender,
        uint256 amount0Out,
        uint256 amount1Out,
        bytes calldata data
    ) external {        
        (address caller, address pair, SwapParams memory params) = abi.decode(data, (address, address, SwapParams));
        require(msg.sender == pair, "not pair");
        require(sender == address(this), "bad sender");
        require(amount0Out == 0 || amount1Out == 0, "one side only");
        
        uint256 amountOut = _swap(params);

        uint256 fee = ((params.amountIn * 3) / 997) + 1;
        uint256 amountToRepay = params.amountIn + fee;

        uint256 profit = amountOut - amountToRepay;
        require(profit > params.minProfit, "profit < min");

        IERC20(params.tokenIn).transfer(pair, amountToRepay);
        IERC20(params.tokenIn).transfer(caller, profit);
    }
}
