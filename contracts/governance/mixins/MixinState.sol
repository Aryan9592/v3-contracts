// SPDX-License-Identifier: Apache 2.0
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

import "./MixinAbstract.sol";
import "./MixinStorage.sol";
import "../interfaces/IGovernanceStrategy.sol";

abstract contract MixinState is MixinStorage, MixinAbstract {
    // TODO: check where we are using this and whether it is correct naming.
    /// @inheritdoc IGovernanceState
    function getDeploymentConstants() external view override returns (DeploymentConstants memory) {
        return
            DeploymentConstants({
                name: name(),
                version: VERSION,
                proposalMaxOperations: PROPOSAL_MAX_OPERATIONS,
                domainTypehash: DOMAIN_TYPEHASH,
                voteTypehash: VOTE_TYPEHASH
            });
    }

    /// @inheritdoc IGovernanceState
    function getProposalById(
        uint256 proposalId
    ) public view override returns (ProposalWrapper memory proposalWrapper) {
        proposalWrapper.proposal = _proposal().proposalById[proposalId];
        uint256 actionsLength = proposalWrapper.proposal.actionsLength;
        ProposedAction[] memory proposedAction = new ProposedAction[](actionsLength);
        for (uint i = 0; i < actionsLength; i++) {
            proposedAction[i] = _proposedAction().proposedActionbyIndex[proposalId][actionsLength];
        }
        proposalWrapper.proposedAction = proposedAction;
    }

    /// @inheritdoc IGovernanceState
    function getProposalState(uint256 proposalId) public view override returns (ProposalState) {
        return _getProposalState(proposalId);
    }

    /// @inheritdoc IGovernanceState
    function getReceipt(uint256 proposalId, address voter) public view override returns (Receipt memory) {
        return _receipt().userReceiptByProposal[proposalId][voter];
    }

    /// @inheritdoc IGovernanceState
    function getVotingPower(address account) external view override returns (uint256) {
        return _getVotingPower(account);
    }

    /// @inheritdoc IGovernanceState
    function governanceParameters() public view override returns (GovernanceParameters memory) {
        return _paramsWrapper().governanceParameters;
    }

    /// @inheritdoc IGovernanceState
    function governanceStrategy() public view override returns (address) {
        return _governanceStrategy().value;
    }

    /// @inheritdoc IGovernanceState
    function name() public view override returns (string memory) {
        return _name().value;
    }

    /// @inheritdoc IGovernanceState
    function proposalCount() public view override returns (uint256 count) {
        return _getProposalCount();
    }

    /// @inheritdoc IGovernanceState
    function proposals() external view override returns (ProposalWrapper[] memory proposalWrapper) {
        uint256 length = _getProposalCount();
        proposalWrapper = new ProposalWrapper[](length);
        for (uint i = 0; i < length; i++) {
            proposalWrapper[i] = getProposalById(length);
        }
    }

    function _getProposalCount() internal view override returns (uint256 count) {
        return _proposalCount().value;
    }

    function _getProposalState(uint256 proposalId) internal view override returns (ProposalState) {
        require(_proposalCount().value >= proposalId, "VOTING_PROPOSAL_ID_ERROR");
        Proposal memory proposal = _proposal().proposalById[proposalId];
        return
            IGovernanceStrategy(_governanceStrategy().value).getProposalState(
                proposal,
                _governanceParameters().quorumThreshold
            );
    }

    function _getVotingPower(address account) internal view override returns (uint256) {
        return IGovernanceStrategy(_governanceStrategy().value).getVotingPower(account);
    }
}
