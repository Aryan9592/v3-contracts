// SPDX-License-Identifier: Apache 2.0
/*

 Copyright 2017-2022 RigoBlock, Rigo Investment Sagl, Rigo Intl.

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

pragma solidity >=0.4.22 <0.9.0;

/// @title Proof of Performance Interface - Allows interaction with the PoP contract.
/// @author Gabriele Rigo - <gab@rigoblock.com>
// solhint-disable-next-line
interface IProofOfPerformance {
    /*
     * CORE FUNCTIONS
     */
    /// @dev Credits the pop reward to the Staking Proxy contract.
    /// @param _poolAddress Address of the pool.
    function creditPopRewardToStakingProxy(address _poolAddress) external;

    /*
     * CONSTANT PUBLIC FUNCTIONS
     */
    /// @dev Returns the proof of performance reward for a pool.
    /// @param _poolAddress Address of the pool.
    /// @return Value of the pop reward in Rigo tokens.
    function proofOfPerformance(address _poolAddress) external view returns (uint256);
}
