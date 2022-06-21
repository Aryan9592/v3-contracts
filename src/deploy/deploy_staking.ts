import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deploy: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment,
) {
  const { deployments, getNamedAccounts } = hre;
  const { deployer } = await getNamedAccounts();
  const { deploy } = deployments;

  // TODO: define grg address, initialize staking
  await deploy("GrgVault", {
    from: deployer,
    args: [
      deployer, // mock grg transfer proxy address
      deployer  // mock grg token address
    ],
    log: true,
    deterministicDeployment: true,
  });

  const staking = await deploy("Staking", {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: true,
  });

  await deploy("StakingProxy", {
    from: deployer,
    args: [staking.address],
    log: true,
    deterministicDeployment: true,
  });
};

deploy.tags = ['staking', 'l2-suite', 'main-suite']
export default deploy;