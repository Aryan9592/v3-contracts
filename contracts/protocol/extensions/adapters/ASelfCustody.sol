// SPDX-License-Identifier: Apache 2.0
/*

 Copyright 2019-2022 RigoBlock, Rigo Intl.

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
pragma solidity =0.8.17;

import "../../../staking/interfaces/IStaking.sol";
import "../../../staking/interfaces/IStorage.sol";
import "../../../staking/interfaces/IGrgVault.sol";
import "./interfaces/IASelfCustody.sol";

/// @title Self Custody adapter - A helper contract for self custody.
/// @author Gabriele Rigo - <gab@rigoblock.com>
// solhint-disable-next-line
contract ASelfCustody is IASelfCustody {
    /// @inheritdoc IASelfCustody
    address public immutable override grgVault;

    // minimum 100k GRG to unlock self custody
    uint128 private constant _MINIMUM_GRG_STAKE = 1e23;

    // bytes4 hash of the transfer selector
    bytes4 private constant _TRANSFER_SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    address private immutable _stakingProxy;
    address private immutable _aSelfCustody;

    constructor(address newGrgVault, address newStakingProxy) {
        grgVault = newGrgVault;
        _stakingProxy = newStakingProxy;
        _aSelfCustody = address(this);
    }

    /// @inheritdoc IASelfCustody
    function transferToSelfCustody(
        address payable selfCustodyAccount,
        address token,
        uint256 amount
    ) external override returns (uint256 shortfall) {
        // we prevent direct calls to this extension
        assert(_aSelfCustody != address(this));
        require(amount != 0, "ASELFCUSTODY_NULL_AMOUNT_ERROR");
        shortfall = poolGrgShortfall(address(this));

        if (shortfall == 0) {
            if (token == address(0)) {
                require(address(this).balance > amount, "ASELFCUSTODY_BALANCE_NOT_ENOUGH_ERROR");
                selfCustodyAccount.transfer(amount);
            } else {
                _safeTransfer(token, selfCustodyAccount, amount);
            }
            emit SelfCustodyTransfer(address(this), selfCustodyAccount, token, amount);
        } else revert("ASELFCUSTODY_MINIMUM_GRG_ERROR");
    }

    /// @inheritdoc IASelfCustody
    function poolGrgShortfall(address targetPool) public view override returns (uint256) {
        address stakingProxy = _getGrgStakingProxy();
        bytes32 poolId = IStorage(stakingProxy).poolIdByRbPoolAccount(targetPool);
        uint256 poolStake = IStaking(stakingProxy).getTotalStakeDelegatedToPool(poolId).currentEpochBalance;

        // we assert the staking implementation has not been compromised by requiring all staked GRG to be delegated to self.
        require(poolStake == IGrgVault(grgVault).balanceOf(targetPool), "ASELFCUSTODY_GRG_BALANCE_MISMATCH_ERROR");
        uint256 minimumStake = _getMinimumGrgStake();

        if (poolStake >= minimumStake) {
            return 0;
        } else {
            unchecked {
                return minimumStake - poolStake;
            }
        }
    }

    /// @dev executes a safe transfer to any ERC20 token
    /// @param token Address of the origin
    /// @param to Address of the target
    /// @param value Amount to transfer
    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) private {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(_TRANSFER_SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "ASELFCUSTODY_TRANSFER_FAILED_ERROR");
    }

    function _getGrgStakingProxy() private view returns (address) {
        return _stakingProxy;
    }

    function _getMinimumGrgStake() private pure returns (uint256) {
        return uint256(_MINIMUM_GRG_STAKE);
    }
}
