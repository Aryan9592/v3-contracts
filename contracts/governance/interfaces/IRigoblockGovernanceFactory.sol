// SPDX-License-Identifier: Apache-2.0-or-later
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

pragma solidity >=0.8.0 <0.9.0;

// solhint-disable-next-line
interface IRigoblockGovernanceFactory {
    /// @notice Emitted when a governance is created.
    /// @param governance Address of the governance proxy.
    event GovernanceCreated(address governance);

    /// @notice Creates a new governance proxy.
    /// @param implementation Address of the governance implementation contract.
    /// @param governanceStrategy Address of the voting strategy.
    /// @param proposalThreshold Number of votes required for creating a new proposal.
    /// @param quorumThreshold Number of votes required for execution.
    /// @param name Human readable string of the name.
    function createGovernance(
        address implementation,
        address governanceStrategy,
        uint256 proposalThreshold,
        uint256 quorumThreshold,
        string calldata name
    ) external returns (address governance);

    struct Parameters {
        /// @notice Address of the governance implementation contract.
        address implementation;

        /// @notice Address of the voting strategy.
        address governanceStrategy;

        /// @notice Number of votes required for creating a new proposal.
        uint256 proposalThreshold;

        /// @notice Number of votes required for execution.
        uint256 quorumThreshold;

        /// @notice String of the name of the application.
        string name;
    }

    /// @notice Returns the pool initialization parameters at proxy deploy.
    /// @return Tuple of the pool parameters.
    function parameters() external view returns (Parameters memory);
}
