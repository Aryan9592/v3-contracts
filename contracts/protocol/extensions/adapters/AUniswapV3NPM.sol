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

import "../../interfaces/IWETH9.sol";
import "../../../utils/exchanges/uniswap/INonfungiblePositionManager/INonfungiblePositionManager.sol";

// TODO: inherit from IAUniswapV3NPM + inheritdocs
contract AUniswapV3NPM {
    // storage must be immutable as needs to be rutime consistent
    bytes4 private constant APPROVE_SELECTOR = bytes4(keccak256(bytes("approve(address,uint256)")));

    // 0xC36442b4a4522E871399CD717aBDD847Ab11FE88 on public networks
    address payable public immutable UNISWAP_V3_NPM_ADDRESS;

    address payable private immutable WethAddress;

    constructor(address _uniswapNpm) {
        UNISWAP_V3_NPM_ADDRESS = payable(_uniswapNpm);
        WethAddress = payable(address(IWETH9(INonfungiblePositionManager(_uniswapNpm).WETH9())));
    }

    // TODO: check under what conditions we could add liquidity with eth and add wrap eth (will be wrapped in multicall before mint)
    /// @notice Creates a new position wrapped in a NFT
    /// @dev Call this when the pool does exist and is initialized. Note that if the pool is created but not initialized
    /// a method does not exist, i.e. the pool is assumed to be initialized.
    /// @param params The params necessary to mint a position, encoded as `MintParams` in calldata
    /// @return tokenId The ID of the token that represents the minted position
    /// @return liquidity The amount of liquidity for this position
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function mint(INonfungiblePositionManager.MintParams memory params)
        external
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        // we first set the allowance to the uniswap position manager
        _safeApprove(params.token0, _getUniswapNpmAddress(), type(uint256).max);
        _safeApprove(params.token1, _getUniswapNpmAddress(), type(uint256).max);

        // only then do we mint the liquidity token
        (tokenId, liquidity, amount0, amount1) = INonfungiblePositionManager(_getUniswapNpmAddress()).mint(
            INonfungiblePositionManager.MintParams({
                token0: params.token0,
                token1: params.token1,
                fee: params.fee,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                recipient: address(this), // this pool is always the recipient
                deadline: params.deadline
            })
        );

        // we make sure we do not clear storage
        _safeApprove(params.token0, _getUniswapNpmAddress(), uint256(1));
        _safeApprove(params.token1, _getUniswapNpmAddress(), uint256(1));
    }

    /// @notice Increases the amount of liquidity in a position, with tokens paid by the `msg.sender`
    /// @param params tokenId The ID of the token for which liquidity is being increased,
    /// amount0Desired The desired amount of token0 to be spent,
    /// amount1Desired The desired amount of token1 to be spent,
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check,
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check,
    /// deadline The time by which the transaction must be included to effect the change
    /// @return liquidity The new liquidity amount as a result of the increase
    /// @return amount0 The amount of token0 to acheive resulting liquidity
    /// @return amount1 The amount of token1 to acheive resulting liquidity
    function increaseLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams memory params)
        external
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        (, , address token0, address token1, , , , , , , , ) =
            INonfungiblePositionManager(_getUniswapNpmAddress()).positions(params.tokenId);

        // we first set the allowance to the uniswap position manager
        _safeApprove(token0, _getUniswapNpmAddress(), type(uint256).max);
        _safeApprove(token1, _getUniswapNpmAddress(), type(uint256).max);

        // finally, we add to the liquidity token
        (liquidity, amount0, amount1) = INonfungiblePositionManager(_getUniswapNpmAddress()).increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: params.tokenId,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                deadline: params.deadline
            })
        );

        // we make sure we do not clear storage
        _safeApprove(token0, _getUniswapNpmAddress(), uint256(1));
        _safeApprove(token1, _getUniswapNpmAddress(), uint256(1));
    }

    /// @notice Decreases the amount of liquidity in a position and accounts it to the position
    /// @param params tokenId The ID of the token for which liquidity is being decreased,
    /// amount The amount by which liquidity will be decreased,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @return amount0 The amount of token0 accounted to the position's tokens owed
    /// @return amount1 The amount of token1 accounted to the position's tokens owed
    function decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata params)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = INonfungiblePositionManager(_getUniswapNpmAddress()).decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: params.tokenId,
                liquidity: params.liquidity,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                deadline: params.deadline
            })
        );
    }

    /// @notice Collects up to a maximum amount of fees owed to a specific position to the recipient
    /// @param params tokenId The ID of the NFT for which tokens are being collected,
    /// recipient The account that should receive the tokens,
    /// amount0Max The maximum amount of token0 to collect,
    /// amount1Max The maximum amount of token1 to collect
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collect(INonfungiblePositionManager.CollectParams memory params)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = INonfungiblePositionManager(_getUniswapNpmAddress()).collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: params.tokenId,
                recipient: address(this), // this pool is always the recipient
                amount0Max: params.amount0Max,
                amount1Max: params.amount1Max
            })
        );
    }

    /// @notice Burns a token ID, which deletes it from the NFT contract. The token must have 0 liquidity and all tokens
    /// must be collected first.
    /// @param tokenId The ID of the token that is being burned
    function burn(uint256 tokenId) external {
        INonfungiblePositionManager(_getUniswapNpmAddress()).burn(tokenId);
    }

    /// @notice Unwraps ETH from WETH9.
    /// @param amountMinimum The minimum amount of WETH9 to unwrap.
    /// @param recipient The address to keep same uniswap npm selector.
    function unwrapWETH9(uint256 amountMinimum, address recipient) external {
        if (recipient != address(this)) { recipient = address(this); }
        IWETH9(_getWethAddress()).withdraw(amountMinimum);
    }

    // TODO: check if better used in custom adapter
    /// @dev Wraps ETH.
    /// @notice Client must wrap if input is native currency.
    /// @param value The ETH amount to be wrapped.
    function wrapETH(uint256 value) external {
        if (value > uint256(0)) {
            IWETH9(WethAddress).deposit{value: value}();
        }
    }

    /// @notice Refunds any ETH balance held by this contract to the `msg.sender`
    /// @dev Useful for bundling with mint or increase liquidity that uses ether, or exact output swaps
    /// that use ether for the input amount
    function refundETH() external {
        INonfungiblePositionManager(_getUniswapNpmAddress()).refundETH();
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
    ) external {
        INonfungiblePositionManager(_getUniswapNpmAddress()).sweepToken(
            token,
            amountMinimum,
            recipient != address(this) ? address(this) : address(this) // this pool is always the recipient
        );
    }

    /// @notice Creates a new pool if it does not exist, then initializes if not initialized
    /// @dev This method can be bundled with others via IMulticall for the first action (e.g. mint) performed against a pool
    /// @param token0 The contract address of token0 of the pool
    /// @param token1 The contract address of token1 of the pool
    /// @param fee The fee amount of the v3 pool for the specified token pair
    /// @param sqrtPriceX96 The initial square root price of the pool as a Q64.96 value
    /// @return pool Returns the pool address based on the pair of tokens and fee, will return the newly created pool address if necessary
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external returns (address pool) {
        pool = INonfungiblePositionManager(_getUniswapNpmAddress()).createAndInitializePoolIfNecessary(
            token0,
            token1,
            fee,
            sqrtPriceX96
        );
    }

    function _safeApprove(
        address token,
        address spender,
        uint256 value
    ) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(APPROVE_SELECTOR, spender, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "AUNISWAPV3NPM_TOKEN_APPROVE_FAILED_ERROR");
    }

    function _getUniswapNpmAddress() private view returns (address) {
        return UNISWAP_V3_NPM_ADDRESS;
    }

    function _getWethAddress() private view returns (address) {
        return WethAddress;
    }
}
