// SPDX-License-Identifier: Apache-2.0-or-later
/*

 Copyright 2021 Rigo Intl.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.

*/

// solhint-disable-next-line
pragma solidity 0.8.14;

import "../../../utils/exchanges/uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../../../utils/exchanges/uniswap/v3-periphery/contracts/interfaces/IPeripheryPaymentsWithFee.sol";
import "../../../utils/exchanges/uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import "../../../utils/exchanges/uniswap/v3-periphery/contracts/libraries/Path.sol";

interface Token {

    function approve(address _spender, uint256 _value) external returns (bool success);

    function allowance(address _owner, address _spender) external view returns (uint256);
    function balanceOf(address _who) external view returns (uint256);
}

/// @title Interface for WETH9
interface IWETH9 {
    /// @notice Deposit ether to get wrapped ether
    function deposit() external payable;

    /// @notice Withdraw wrapped ether to get ether
    function withdraw(uint256) external;
}

contract AUniswapV3 {

    using Path for bytes;

    // TODO: initialize in constructor
    address payable immutable private UNISWAP_V3_SWAP_ROUTER_ADDRESS = payable(address(0xE592427A0AEce92De3Edee1F18E0157C05861564));

    // TODO: calculate sig hashes and add explanation in comment to save gas, make constants.
    bytes4 immutable private APPROVE_SELECTOR = bytes4(keccak256(bytes("approve(address,uint256)")));
    bytes4 immutable private EXACT_INPUT_SELECTOR = bytes4(keccak256("exactInput(ISwapRouter.ExactInputParams)"));
    bytes4 immutable private EXACT_INPUT_SINGLE_SELECTOR = bytes4(keccak256("exactInputSingle(ISwapRouter.ExactInputSingleParams)"));
    bytes4 immutable private EXACT_OUTPUT_SELECTOR = bytes4(keccak256("exactOutput(ISwapRouter.exactOutputParams)"));
    bytes4 immutable private EXACT_OUTPUT_SINGLE_SELECTOR = bytes4(keccak256("exactOutputSingle(ISwapRouter.ExactOutputSingleParams)"));
    bytes4 immutable private REFUND_ETH_SELECTOR = bytes4(keccak256("refundETH()"));
    bytes4 immutable private SWEEP_TOKEN_SELECTOR = bytes4(keccak256("sweepToken(address,uint256,address)"));
    bytes4 immutable private SWEEP_TOKEN_WITH_FEE_SELECTOR = bytes4(keccak256("sweepTokenWithFee(address,uint256,address,uint256,address)"));
    bytes4 immutable private UNWRAP_WETH9_SELECTOR = bytes4(keccak256("unwrapWETH9(uint256,address)"));
    bytes4 immutable private UNWRAP_WETH9_WITH_FEE_SELECTOR = bytes4(keccak256("unwrapWETH9WithFee(uint256,address,uint256,address)"));
    bytes4 immutable private WRAP_ETH_SELECTOR = bytes4(keccak256("wrapETH(uint256)"));

    /// @notice Call multiple functions in the current contract and return the data from all of them if they all succeed
    /// @dev The `msg.value` should not be trusted for any method callable from multicall.
    /// @param data The encoded function data for each of the calls to make to this contract
    function multicall(bytes[] calldata data) external payable {
        for (uint256 i = 0; i < data.length; i++) {
            bytes memory messagePack = data[i];
            bytes4 selector;
            assembly {
                selector := mload(add(messagePack, 32))
            }

            if (selector == EXACT_INPUT_SINGLE_SELECTOR) {
                _exactInputSingle(abi.decode(data[i], (ISwapRouter.ExactInputSingleParams)));
            } else if (selector == EXACT_INPUT_SELECTOR) {
                _exactInput(abi.decode(data[i], (ISwapRouter.ExactInputParams)));
            } else if (selector == EXACT_OUTPUT_SINGLE_SELECTOR) {
                _exactOutputSingle(abi.decode(data[i], (ISwapRouter.ExactOutputSingleParams)));
            } else if (selector == EXACT_OUTPUT_SELECTOR) {
                _exactOutput(abi.decode(data[i], (ISwapRouter.ExactOutputParams)));
            } else if (selector == WRAP_ETH_SELECTOR) {
                _wrapETH(abi.decode(data[i], (uint256)));
            } else if (selector == UNWRAP_WETH9_SELECTOR) {
                (uint256 amountMinimum, address recipient) = abi.decode(data[i], (uint256, address));
                _unwrapWETH9(amountMinimum, recipient);
            } else if (selector == REFUND_ETH_SELECTOR) {
                _refundETH();
            } else if (selector == SWEEP_TOKEN_SELECTOR) {
                (address token, uint256 amountMinimum, address recipient) = abi.decode(
                    data[i],
                    (address, uint256, address)
                );
                _sweepToken(token, amountMinimum, recipient);
            } else if (selector == UNWRAP_WETH9_WITH_FEE_SELECTOR) {
                (uint256 amountMinimum, address recipient, uint256 feeBips, address feeRecipient) = abi.decode(
                    data[i],
                    (uint256, address, uint256, address)
                );
                _unwrapWETH9WithFee(amountMinimum, recipient, feeBips, feeRecipient);
            } else if (selector == SWEEP_TOKEN_WITH_FEE_SELECTOR) {
                (
                    address token,
                    uint256 amountMinimum,
                    address recipient,
                    uint256 feeBips,
                    address feeRecipient
                ) = abi.decode(
                    data[i],
                    (address, uint256, address, uint256, address)
                );
                _sweepTokenWithFee(token, amountMinimum, recipient, feeBips, feeRecipient);
            } else revert("UNKNOWN_SELECTOR");
        }
    }

    // TODO: calculate gas cost different of making methods public instead of external+internal
    /// @notice Wraps ETH when value input is non-null
    /// @param value The ETH amount to be wrapped
    function wrapETH(uint256 value) external payable {
        _wrapETH(value);
    }

    function _wrapETH(uint256 value) internal {
        if (value > uint256(0)) {
            IWETH9(
                IPeripheryImmutableState(UNISWAP_V3_SWAP_ROUTER_ADDRESS).WETH9()
            ).deposit{value: value}();
        }
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in memory
    /// @return amountOut The amount of the received token
    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut)
    {
        amountOut = _exactInputSingle(params);
    }

    function _exactInputSingle(ISwapRouter.ExactInputSingleParams memory params)
        internal
        returns (uint256 amountOut)
    {
        // we first set the allowance to the uniswap router
        _safeApprove(params.tokenIn, UNISWAP_V3_SWAP_ROUTER_ADDRESS, type(uint).max);

        // finally, we swap the tokens
        amountOut = ISwapRouter(UNISWAP_V3_SWAP_ROUTER_ADDRESS).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: params.tokenIn,
                tokenOut: params.tokenOut,
                fee: params.fee,
                recipient: address(this), // this pool is always the recipient
                deadline: params.deadline,
                amountIn: params.amountIn,
                amountOutMinimum: params.amountOutMinimum,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        // we make sure we do not clear storage
        _safeApprove(params.tokenIn, UNISWAP_V3_SWAP_ROUTER_ADDRESS, uint256(1));
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in memory
    /// @return amountOut The amount of the received token
    function exactInput(ISwapRouter.ExactInputParams calldata params)
        external
        payable
        returns (uint256 amountOut)
    {
        amountOut = _exactInput(params);
    }

    function _exactInput(ISwapRouter.ExactInputParams memory params)
        internal
        returns (uint256 amountOut)
    {
        (address tokenIn, , ) = params.path.decodeFirstPool();

        // we first set the allowance to the uniswap router
        _safeApprove(tokenIn, UNISWAP_V3_SWAP_ROUTER_ADDRESS, type(uint).max);

        // finally, we swap the tokens
        amountOut = ISwapRouter(UNISWAP_V3_SWAP_ROUTER_ADDRESS).exactInput(
            ISwapRouter.ExactInputParams({
                path: params.path,
                recipient: address(this), // this pool is always the recipient
                deadline: params.deadline,
                amountIn: params.amountIn,
                amountOutMinimum: params.amountOutMinimum
            })
        );

        // we make sure we do not clear storage
        _safeApprove(tokenIn, UNISWAP_V3_SWAP_ROUTER_ADDRESS, uint256(1));
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactOutputSingleParams` in memory
    /// @return amountIn The amount of the input token
    function exactOutputSingle(ISwapRouter.ExactOutputSingleParams calldata params)
        external
        payable
        returns (uint256 amountIn)
    {
        amountIn = _exactOutputSingle(params);
    }

    function _exactOutputSingle(ISwapRouter.ExactOutputSingleParams memory params)
        internal
        returns (uint256 amountIn)
    {
        // we first set the allowance to the uniswap router
        _safeApprove(params.tokenIn, UNISWAP_V3_SWAP_ROUTER_ADDRESS, type(uint).max);

        // finally, we swap the tokens
        amountIn = ISwapRouter(UNISWAP_V3_SWAP_ROUTER_ADDRESS).exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: params.tokenIn,
                tokenOut: params.tokenOut,
                fee: params.fee,
                recipient: address(this), // this pool is always the recipient
                deadline: params.deadline,
                amountOut: params.amountOut,
                amountInMaximum: params.amountInMaximum,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        // we make sure we do not clear storage
        _safeApprove(params.tokenIn, UNISWAP_V3_SWAP_ROUTER_ADDRESS, uint256(1));
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another along the specified path (reversed)
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactOutputParams` in memory
    /// @return amountIn The amount of the input token
    function exactOutput(ISwapRouter.ExactOutputParams calldata params)
        external
        payable
        returns (uint256 amountIn)
    {
        amountIn = _exactOutput(params);
    }

    function _exactOutput(ISwapRouter.ExactOutputParams memory params)
        internal
        returns (uint256 amountIn)
    {
        (address tokenIn, , ) = params.path.decodeFirstPool();

        // we first set the allowance to the uniswap router
        _safeApprove(tokenIn, UNISWAP_V3_SWAP_ROUTER_ADDRESS, type(uint).max);

        // finally, we swap the tokens
        amountIn = ISwapRouter(UNISWAP_V3_SWAP_ROUTER_ADDRESS).exactOutput(
            ISwapRouter.ExactOutputParams({
                path: params.path,
                recipient: address(this), // this pool is always the recipient
                deadline: params.deadline,
                amountOut: params.amountOut,
                amountInMaximum: params.amountInMaximum
            })
        );

        // we make sure we do not clear storage
        _safeApprove(tokenIn, UNISWAP_V3_SWAP_ROUTER_ADDRESS, uint256(1));
    }

    /// @notice Unwraps the contract's WETH9 balance and sends it to recipient as ETH.
    /// @dev The amountMinimum parameter prevents malicious contracts from stealing WETH9 from users.
    /// @param amountMinimum The minimum amount of WETH9 to unwrap
    /// @param recipient The address receiving ETH
    function unwrapWETH9(uint256 amountMinimum, address recipient)
        external
        payable
    {
        _unwrapWETH9(amountMinimum, recipient);
    }

    function _unwrapWETH9(uint256 amountMinimum, address recipient)
        internal
    {
        IPeripheryPaymentsWithFee(UNISWAP_V3_SWAP_ROUTER_ADDRESS).unwrapWETH9(
            amountMinimum,
            recipient != address(this) ? address(this) : address(this) // this pool is always the recipient
        );
    }

    /// @notice Refunds any ETH balance held by this contract to the `msg.sender`
    /// @dev Useful for bundling with mint or increase liquidity that uses ether, or exact output swaps
    /// that use ether for the input amount
    function refundETH()
        external
        payable
    {
        _refundETH();
    }

    function _refundETH()
        internal
    {
        IPeripheryPaymentsWithFee(UNISWAP_V3_SWAP_ROUTER_ADDRESS).refundETH();
    }

    /// @notice Transfers the full amount of a token held by this contract to recipient
    /// @dev The amountMinimum parameter prevents malicious contracts from stealing the token from users
    /// @param token The contract address of the token which will be transferred to `recipient`
    /// @param amountMinimum The minimum amount of token required for a transfer
    /// @param recipient The destination address of the token
    function sweepToken(
        address token,
        uint256 amountMinimum,
        address recipient
    )
        external
        payable
    {
        _sweepToken(token, amountMinimum, recipient);
    }

    function _sweepToken(
        address token,
        uint256 amountMinimum,
        address recipient
    )
        internal
    {
        IPeripheryPaymentsWithFee(UNISWAP_V3_SWAP_ROUTER_ADDRESS).sweepToken(
            token,
            amountMinimum,
            recipient != address(this) ? address(this) : address(this) // this pool is always the recipient
        );
    }

    /// @notice Unwraps the contract's WETH9 balance and sends it to recipient as ETH, with a percentage between
    /// 0 (exclusive), and 1 (inclusive) going to feeRecipient
    /// @dev The amountMinimum parameter prevents malicious contracts from stealing WETH9 from users.
    function unwrapWETH9WithFee(
        uint256 amountMinimum,
        address recipient,
        uint256 feeBips,
        address feeRecipient
    )
        external
        payable
    {
        _unwrapWETH9WithFee(amountMinimum, recipient, feeBips, feeRecipient);
    }

    function _unwrapWETH9WithFee(
        uint256 amountMinimum,
        address recipient,
        uint256 feeBips,
        address feeRecipient
    )
        internal
    {
        IPeripheryPaymentsWithFee(UNISWAP_V3_SWAP_ROUTER_ADDRESS).unwrapWETH9WithFee(
            amountMinimum,
            recipient != address(this) ? address(this) : address(this),  // this pool is always the recipient
            feeBips,
            feeRecipient
        );
    }

    /// @notice Transfers the full amount of a token held by this contract to recipient, with a percentage between
    /// 0 (exclusive) and 1 (inclusive) going to feeRecipient
    /// @dev The amountMinimum parameter prevents malicious contracts from stealing the token from users
    function sweepTokenWithFee(
        address token,
        uint256 amountMinimum,
        address recipient,
        uint256 feeBips,
        address feeRecipient
    )
        external
        payable
    {
        _sweepTokenWithFee(token, amountMinimum, recipient, feeBips, feeRecipient);
    }

    function _sweepTokenWithFee(
        address token,
        uint256 amountMinimum,
        address recipient,
        uint256 feeBips,
        address feeRecipient
    )
        internal
    {
        IPeripheryPaymentsWithFee(UNISWAP_V3_SWAP_ROUTER_ADDRESS).sweepTokenWithFee(
            token,
            amountMinimum,
            recipient != address(this) ? address(this) : address(this),  // this pool is always the recipient
            feeBips,
            feeRecipient
        );
    }

    function _safeApprove(
        address token,
        address spender,
        uint256 value
    )
        internal
    {
        // solhint-disable-next-line avoid-low-level-calls
        // TODO: check additional gas cost in calling contract instead of address with selector or use assembly
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(APPROVE_SELECTOR, spender, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "AUNISWAPV3_TOKEN_APPROVE_FAILED_ERROR"
        );
    }
}
