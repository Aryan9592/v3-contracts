// SPDX-License-Identifier: Apache 2.0
/*

 Copyright 2017-2022 RigoBlock, Rigo Investment Sagl.

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

pragma solidity 0.8.17;

import {OwnedUninitialized as Owned} from "../../utils/owned/OwnedUninitialized.sol";
import {LibSanitize} from "../../utils/libSanitize/LibSanitize.sol";
import {IAuthorityCore as Authority} from "../interfaces/IAuthorityCore.sol";

import {IPoolRegistry} from "../interfaces/IPoolRegistry.sol";

/// @title Pool Registry - Allows registration of pools.
/// @author Gabriele Rigo - <gab@rigoblock.com>
// solhint-disable-next-line
contract PoolRegistry is IPoolRegistry {
    /// @inheritdoc IPoolRegistry
    address public override authority;

    /// @inheritdoc IPoolRegistry
    address public override rigoblockDaoAddress;

    mapping(address => bytes32) private mapIdByAddress;

    mapping(address => PoolMeta) private poolMetaByAddress;

    struct PoolMeta {
        mapping(bytes32 => bytes32) meta;
    }

    /*
     * MODIFIERS
     */
    modifier onlyWhitelistedFactory {
        require(Authority(authority).isWhitelistedFactory(msg.sender), "REGISTRY_FACTORY_NOT_WHITELISTED_ERROR");
        _;
    }

    modifier onlyPoolOwner(address _poolAddress) {
        require(Owned(_poolAddress).owner() == msg.sender, "REGISTRY_CALLER_IS_NOT_POOL_OWNER_ERROR");
        _;
    }

    modifier onlyRigoblockDao {
        require(msg.sender == rigoblockDaoAddress, "REGISTRY_CALLER_NOT_DAO_ERROR");
        _;
    }

    modifier whenAddressFree(address _poolAddress) {
        require(mapIdByAddress[_poolAddress] == bytes32(0), "REGISTRY_ADDRESS_ALREADY_TAKEN_ERROR");
        _;
    }

    modifier whenPoolRegistered(address _poolAddress) {
        require(mapIdByAddress[_poolAddress] != bytes32(0), "REGISTRY_ADDRESS_NOT_REGISTERED_ERROR");
        _;
    }

    constructor(address _authority, address _rigoblockDao) {
        authority = _authority;
        rigoblockDaoAddress = _rigoblockDao;
    }

    /*
     * CORE FUNCTIONS
     */
    /// @inheritdoc IPoolRegistry
    function register(
        address _poolAddress,
        string calldata _name,
        string calldata _symbol,
        bytes32 poolId
    ) external override onlyWhitelistedFactory whenAddressFree(_poolAddress) {
        _assertValidNameAndSymbol(_name, _symbol);
        mapIdByAddress[_poolAddress] = poolId;

        emit Registered(
            msg.sender, // proxy factory
            _poolAddress,
            bytes32(bytes(_name)),
            bytes32(bytes(_symbol)),
            poolId
        );
    }

    /// @inheritdoc IPoolRegistry
    function setAuthority(address _authority) external override onlyRigoblockDao {
        require(_authority != authority, "REGISTRY_SAME_INPUT_ADDRESS_ERROR");
        require(_isContract(_authority), "REGISTRY_NEW_AUTHORITY_NOT_CONTRACT_ERROR");
        authority = _authority;
        emit AuthorityChanged(_authority);
    }

    /// @inheritdoc IPoolRegistry
    function setMeta(
        address _poolAddress,
        bytes32 _key,
        bytes32 _value
    ) external override onlyPoolOwner(_poolAddress) whenPoolRegistered(_poolAddress) {
        poolMetaByAddress[_poolAddress].meta[_key] = _value;
        emit MetaChanged(_poolAddress, _key, _value);
    }

    /// @inheritdoc IPoolRegistry
    function setRigoblockDao(address _newRigoblockDao) external override onlyRigoblockDao {
        require(_newRigoblockDao != rigoblockDaoAddress, "REGISTRY_SAME_INPUT_ADDRESS_ERROR");
        require(_isContract(_newRigoblockDao), "REGISTRY_NEW_DAO_NOT_CONTRACT_ERROR");
        rigoblockDaoAddress = _newRigoblockDao;
        emit RigoblockDaoChanged(_newRigoblockDao);
    }

    /*
     * CONSTANT PUBLIC FUNCTIONS
     */
    /// @inheritdoc IPoolRegistry
    function getPoolIdFromAddress(address _poolAddress) external view override returns (bytes32 poolId) {
        poolId = mapIdByAddress[_poolAddress];
    }

    /// @inheritdoc IPoolRegistry
    function getMeta(address _poolAddress, bytes32 _key) external view override returns (bytes32 poolMeta) {
        return poolMetaByAddress[_poolAddress].meta[_key];
    }

    /*
     * INTERNAL FUNCTIONS
     */
    function _assertValidNameAndSymbol(string memory _name, string memory _symbol) internal pure {
        uint256 nameLength = bytes(_name).length;
        // we always want to keep name lenght below 32, for logging bytes32.
        require(nameLength >= uint256(4) && nameLength <= uint256(32), "REGISTRY_NAME_LENGTH_ERROR");

        uint256 symbolLength = bytes(_symbol).length;
        require(symbolLength >= uint256(3) && symbolLength <= uint256(5), "REGISTRY_SYMBOL_LENGTH_ERROR");

        // check valid characters in name and symbol
        LibSanitize.assertIsValidCheck(_name);
        LibSanitize.assertIsValidCheck(_symbol);
        LibSanitize.assertIsUppercase(_symbol);
    }

    function _isContract(address _target) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_target)
        }
        return size > 0;
    }
}
