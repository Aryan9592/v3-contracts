import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { AddressZero } from "@ethersproject/constants"

const deploy: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment,
) {
  const { deployments, getNamedAccounts } = hre;
  const { deployer } = await getNamedAccounts();
  const { deploy } = deployments;

  const authority = await deploy("Authority", {
    from: deployer,
    args: [deployer], // owner
    log: true,
    deterministicDeployment: true,
  });

  const registry = await deploy("PoolRegistry", {
    from: deployer,
    args: [
      authority.address,
      deployer  // Rigoblock Dao
    ],
    log: true,
    deterministicDeployment: true,
  });

  // same on altchains but different from one deployed on Ethereum
  const rigoToken = { address: "0x09188484e1Ab980DAeF53a9755241D759C5B7d60" };

  const grgTransferProxy = await deploy("ERC20Proxy", {
    from: deployer,
    args: [deployer],  // Authorizable(_owner)
    log: true,
    deterministicDeployment: true,
  });

  // same on altchains but different from one deployed on Ethereum
  const grgVault = await deploy("GrgVault", {
    from: deployer,
    args: [
      grgTransferProxy.address,
      rigoToken.address,
      deployer  // Authorizable(_owner)
    ],
    log: true,
    deterministicDeployment: true,
  });

  // same on altchains but different from one deployed on Ethereum
  const staking = await deploy("Staking", {
    from: deployer,
    args: [
        grgVault.address,
        registry.address,
        rigoToken.address
    ],
    log: true,
    deterministicDeployment: true,
  });

  // same on altchains but different from one deployed on Ethereum
  const stakingProxy = await deploy("StakingProxy", {
    from: deployer,
    args: [
        staking.address,
        deployer  // Authorizable(_owner)
    ],
    log: true,
    deterministicDeployment: true,
  });

  const governanceFactory = await deploy("RigoblockGovernanceFactory", {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: true,
  });

  const governanceImplementation = await deploy("RigoblockGovernance", {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: true,
  });

  const governanceStrategy = await deploy("RigoblockGovernanceStrategy", {
    from: deployer,
    args: [stakingProxy.address],
    log: true,
    deterministicDeployment: true,
  });
};

deploy.tags = ['governance-tests', 'l2-suite', 'main-suite']
export default deploy;
