// SPDX-License-Identifier: Apache-2.0
/*

  Copyright 2023 Rigo Intl.

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

interface IGovernanceEvents {
    event ThresholdsUpdated(uint256 proposalThreshold, uint256 quorumThreshold);

    /// @notice Emitted when implementation written to proxy storage.
    /// @dev Emitted also at first variable initialization.
    /// @param newImplementation Address of the new implementation.
    event Upgraded(address indexed newImplementation);

    struct ProposedAction {
        address target;
        bytes data;
        uint256 value;
    }

    event ProposalCreated(
        address proposer,
        uint256 proposalId,
        ProposedAction[] actions,
        uint256 executionEpoch,
        string description
    );

    // TODO: add docs
    enum VoteType {
        FOR,
        AGAINST,
        ABSTAIN
    }

    event VoteCast(address voter, uint256 proposalId, VoteType voteType, uint256 votingPower);

    event ProposalExecuted(uint256 proposalId);
}
