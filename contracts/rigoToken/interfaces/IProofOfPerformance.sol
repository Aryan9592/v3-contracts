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

pragma solidity >=0.4.22 <0.8.0;

/// @title Proof of Performance Interface - Allows interaction with the PoP contract.
/// @author Gabriele Rigo - <gab@rigoblock.com>
// solhint-disable-next-line
interface IProofOfPerformance {

    /*
     * PUBLIC VARIABLES
     */
    function rigoblockDaoAddress()
        external
        view
        returns (address);

    function authorityAddress()
        external
        view
        returns (address);

    /*
     * CORE FUNCTIONS
     */
    /// @dev Credits the pop reward to the Staking Proxy contract.
    /// @param _poolAddress Address of the pool.
    function creditPopRewardToStakingProxy(address _poolAddress)
        external;

    /// @dev Allows RigoBlock Dao to update the pools registry.
    /// @param _newPoolRegistryAddress Address of new registry.
    function setRegistry(address _newPoolRegistryAddress)
        external;

    /// @dev Allows RigoBlock Dao to update its address.
    /// @param newRigoblockDaoAddress Address of new dao.
    function setRigoblockDao(address newRigoblockDaoAddress)
        external;

    /// @dev Allows rigoblock dao to update the authority.
    /// @param newAuthorityAddress Address of the authority.
    function setAuthority(address newAuthorityAddress)
        external;

    /// @dev Allows RigoBlock Dao to set the parameters for a group.
    /// @param groupAddress Address of the pool's group.
    /// @param ratio Value of the ratio between assets and performance reward for a group.
    /// @param inflationFactor Value of the reward factor for a group.
    /// @notice onlyRigoblockDao can set ratio.
    function setGroupParams(
        address groupAddress,
        uint256 ratio,
        uint256 inflationFactor
    )
        external;

    /*
     * CONSTANT PUBLIC FUNCTIONS
     */
    /// @dev Gets data of a pool.
    /// @param _poolAddress Address of the pool.
    /// @return poolGroup Address of the pool factory.
    /// @return poolPrice Price of the pool in wei.
    /// @return poolSupply Total supply of the pool in units.
    /// @return poolValue Total value of the pool in wei.
    /// @return epochReward Value of the reward factor or said pool.
    /// @return ratio Of assets/performance reward (from 0 to 10000).
    /// @return pop Value of the pop reward to be claimed in GRGs.
    /// @return poolId Id of the pool.
    function getPoolData(address _poolAddress)
        external
        view
        returns (
            address poolGroup,
            uint256 poolPrice,
            uint256 poolSupply,
            uint256 poolValue,
            uint256 epochReward,
            uint256 ratio,
            uint256 pop,
            bytes32 poolId
        );

    /// @dev Returns the highwatermark of a pool.
    /// @param poolId Id of the pool.
    /// @return Value of the all-time-high pool nav.
    function getHwm(bytes32 poolId)
        external
        view
        returns (uint256);

    /// @dev Returns the address and the group of a pool from its id.
    /// @param _poolAddress Address of the target pool.
    /// @return poolId Id of the target pool.
    function getPoolIdFromAddress(address _poolAddress)
        external
        view
        returns (bytes32 poolId);

    /// @dev Returns the split ratio of asset and performance reward.
    /// @param _poolAddress Address of the pool.
    /// @return epochReward Value of the reward factor.
    /// @return epochTime Value of epoch time.
    /// @return ratio Value of the ratio from 1 to 100.
    function getRewardParameters(address _poolAddress)
        external
        view
        returns (
            uint256 epochReward,
            uint256 epochTime,
            uint256 ratio
        );

    /// @dev Returns the proof of performance reward for a pool.
    /// @param _poolAddress Address of the pool.
    /// @return popReward Value of the pop reward in Rigo tokens.
    /// @return performanceReward Split of the performance reward in Rigo tokens.
    /// @notice epoch reward should be big enough that it.
    /// @notice can be decreased if number of funds increases.
    /// @notice should be at least 10^6 (just as pool base) to start with.
    /// @notice rigo token has 10^18 decimals.
    function proofOfPerformance(address _poolAddress)
        external
        view
        returns (
            uint256 popReward,
            uint256 performanceReward);

    /// @dev Returns the price a pool from its id.
    /// @param _poolAddress Address of the pool.
    /// @return poolPrice Price of the pool in wei.
    /// @return totalTokens Number of tokens of a pool (totalSupply).
    function getPoolPrice(address _poolAddress)
        external
        view
        returns (
            uint256 poolPrice,
            uint256 totalTokens
        );

    /// @dev Returns the value of a pool from its id.
    /// @param _poolAddress Address of the pool.
    /// @return aum Total value of the pool in ETH.
    function calcPoolValue(address _poolAddress)
        external
        view
        returns (uint256 aum);
}
