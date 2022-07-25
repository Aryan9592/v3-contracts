import { expect } from "chai";
import hre, { deployments, waffle, ethers } from "hardhat";
import "@nomiclabs/hardhat-ethers";
import { AddressZero } from "@ethersproject/constants";
import { parseEther } from "@ethersproject/units";
import { BigNumber, Contract } from "ethers";
import { calculateProxyAddress, calculateProxyAddressWithCallback } from "../../src/utils/proxies";
import { deployContract, timeTravel } from "../utils/utils";
import { getAddress } from "ethers/lib/utils";

describe("Inflation", async () => {
    const [ user1, user2 ] = waffle.provider.getWallets()

    const setupTests = deployments.createFixture(async ({ deployments }) => {
        await deployments.fixture('tests-setup')
        const RigoblockPoolProxyFactory = await deployments.get("RigoblockPoolProxyFactory")
        const Factory = await hre.ethers.getContractFactory("RigoblockPoolProxyFactory")
        const StakingProxyInstance = await deployments.get("StakingProxy")
        const Staking = await hre.ethers.getContractFactory("Staking")
        const InflationInstance = await deployments.get("Inflation")
        const Inflation = await hre.ethers.getContractFactory("Inflation")
        const RigoTokenInstance = await deployments.get("RigoToken")
        const RigoToken = await hre.ethers.getContractFactory("RigoToken")
        const factory = Factory.attach(RigoblockPoolProxyFactory.address)
        const { newPoolAddress, poolId } = await factory.callStatic.createPool(
            'testpool',
            'TEST',
            AddressZero
        )
        await factory.createPool('testpool','TEST',AddressZero)
        return {
            inflation: Inflation.attach(InflationInstance.address),
            rigoToken: RigoToken.attach(RigoTokenInstance.address),
            stakingProxy: Staking.attach(StakingProxyInstance.address),
            newPoolAddress,
            poolId
        }
    });

    describe("mintInflation", async () => {
        it('should revert if caller not staking proxy', async () => {
            const { inflation } = await setupTests()
            await expect(
                inflation.mintInflation()
            ).to.be.revertedWith("CALLER_NOT_STAKING_PROXY_ERROR")
        })

        it('should revert if epoch time shortened but time not enough', async () => {
            const { inflation, stakingProxy } = await setupTests()
            await timeTravel({ days: 14, mine:true })
            await stakingProxy.endEpoch()
            const minimumPoolStake = parseEther("100") // 100 GRG
            await stakingProxy.addAuthorizedAddress(user1.address)
            await stakingProxy.setParams(
                432001,  //uint256 _epochDurationInSeconds,
                100,    //uint32 _rewardDelegatedStakeWeight,
                minimumPoolStake,    //uint256 _minimumPoolStake,
                2,      //uint32 _cobbDouglasAlphaNumerator,
                3       //uint32 _cobbDouglasAlphaDenominator
            )
            // error in inflation will never be returned as staking will revert first
            await expect(
                stakingProxy.endEpoch()
            ).to.be.revertedWith("STAKING_TIMESTAMP_TOO_LOW_ERROR")
        })

        it('should wait for epoch 2 before first mint', async () => {
            const { inflation, stakingProxy, rigoToken } = await setupTests()
            expect(await inflation.epochEnded()).to.be.eq(true)
            await expect(
                stakingProxy.endEpoch()
            ).to.be.revertedWith("STAKING_TIMESTAMP_TOO_LOW_ERROR")
            await timeTravel({ days: 14, mine:true })
            await expect(
                stakingProxy.endEpoch()
            ).to.emit(stakingProxy, "EpochFinalized").withArgs(1, 0, 0)
            //expect(await inflation.epochEnded()).to.be.eq(false)
            expect(await rigoToken.balanceOf(stakingProxy.address)).to.be.eq(0)
            await timeTravel({ days: 14, mine:true })
            await expect(
                stakingProxy.endEpoch()
            ).to.emit(stakingProxy, "GrgMintEvent")
            const mintedAmount = await inflation.getEpochInflation()
            expect(await rigoToken.balanceOf(stakingProxy.address)).to.be.not.eq(0)
        })

        // when deploying on alt-chains we must set rigoblock dao to address 0 in Rigo token after setup
        it('should not allow changing rigoblock address in grg after set to 0', async () => {
            const { inflation, stakingProxy, rigoToken } = await setupTests()
            expect(await rigoToken.minter()).to.be.eq(inflation.address)
            await expect(rigoToken.mintToken(AddressZero, 5)).to.be.reverted
            await rigoToken.changeMintingAddress(user2.address)
            await expect(
                rigoToken.connect(user2).mintToken(AddressZero, 5)
            ).to.emit(rigoToken, "TokenMinted").withArgs(AddressZero, 5)
            // GRG does not return rich errors. Note: we set minter to 0 after initial setup
            await rigoToken.changeRigoblockAddress(AddressZero)
            await expect(rigoToken.changeMintingAddress(user1.address)).to.be.reverted
            await expect(rigoToken.mintToken(AddressZero, 5)).to.be.reverted
        })

        // this test should assure that a rogue upgrade of staking implementation won't affect token issuance
        it('should revert on time anomalies', async () => {
            const { inflation, stakingProxy, rigoToken } = await setupTests()
            const StakingProxyInstance = await deployments.get("StakingProxy")
            const StakingProxy = await hre.ethers.getContractFactory("StakingProxy")
            const proxy = StakingProxy.attach(StakingProxyInstance.address)
            // we must preserve storage in order to overwrite the correct storage slot
            // unfortunately we must declare all preceding variables
            const source = `
            contract RogueStaking {
                address public owner;
                mapping(address => bool) public authorized;
                address[] public authorities;
                address public stakingContract;
                mapping(uint8 => StoredBalance) internal _globalStakeByStatus;
                mapping(uint8 => mapping(address => StoredBalance)) internal _ownerStakeByStatus;
                mapping(address => mapping(bytes32 => StoredBalance)) internal _delegatedStakeToPoolByOwner;
                mapping(bytes32 => StoredBalance) internal _delegatedStakeByPoolId;
                mapping(address => bytes32) public poolIdByRbPoolAccount;
                mapping(bytes32 => Pool) internal _poolById;
                mapping(bytes32 => uint256) public rewardsByPoolId;
                uint256 public currentEpoch;
                uint256 public currentEpochStartTimeInSeconds;
                mapping(bytes32 => mapping(uint256 => Fraction)) internal _cumulativeRewardsByPool;
                mapping(bytes32 => uint256) internal _cumulativeRewardsByPoolLastStored;
                mapping(address => bool) public validPops;
                uint256 public epochDurationInSeconds;
                uint32 public rewardDelegatedStakeWeight; // 1e15
                uint256 public minimumPoolStake; // 1e19
                uint32 public cobbDouglasAlphaNumerator; // 2
                uint32 public cobbDouglasAlphaDenominator; // 3
                address public inflation;
                struct PoolStats { uint256 feesCollected; uint256 weightedStake; uint256 membersStake; }
                struct AggregatedStats { uint256 rewardsAvailable; uint256 numPoolsToFinalize; uint256 totalFeesCollected; uint256 totalWeightedStake; uint256 totalRewardsFinalized; }
                struct StoredBalance { uint64 currentEpoch; uint96 currentEpochBalance; uint96 nextEpochBalance; }
                struct Pool { address operator; address stakingPal; uint32 operatorShare; uint32 stakingPalShare; }
                struct Fraction { uint256 numerator; uint256 denominator; }
                function init() public {}
                function setDuration(uint256 _duration) public { epochDurationInSeconds = _duration; }
                function setStaking(address _staking) public { stakingContract = _staking; }
                function setInflation(address _inflation) public { inflation = _inflation; }
                function endEpoch() public returns (uint256) {
                    bytes4 selector = bytes4(keccak256(bytes("mintInflation()")));
                    bytes memory encodedCall = abi.encodeWithSelector(selector);
                    (bool success, bytes memory data) = inflation.call(encodedCall);
                    if (!success) { revert(string(data)); } return uint256(bytes32(data));
                }
                function getInflation() public view returns (uint256) {
                    bytes4 selector = bytes4(keccak256(bytes("getEpochInflation()")));
                    bytes memory encodedCall = abi.encodeWithSelector(selector);
                    ( , bytes memory data) = inflation.staticcall(encodedCall);
                    return uint256(bytes32(data));
                }
                function getParams() external view returns (uint256, uint32, uint256, uint32, uint32) {
                    return (epochDurationInSeconds, 1, 1, 1, 1);
                }
            }`
            const rogueImplementation = await deployContract(user1, source)
            const rogueProxy = rogueImplementation.attach(proxy.address)
            await proxy.addAuthorizedAddress(user1.address)
            await expect(
                proxy.detachStakingContract()
            ).to.emit(proxy, "StakingContractDetachedFromProxy")
            await expect(stakingProxy.endEpoch()).to.be.revertedWith("STAKING_ADDRESS_NULL_ERROR")
            await expect(
                proxy.attachStakingContract(rogueImplementation.address)
            ).to.be.emit(proxy, "StakingContractAttachedToProxy").withArgs(rogueImplementation.address)
            await rogueProxy.setInflation(inflation.address)
            // TODO: following tests work, but do not return expected errror
            // max 90 days duration
            await rogueProxy.setDuration(77760001)
            await expect(rogueProxy.endEpoch()).to.be.revertedWith("INFLATION_TIME_ANOMALY_ERROR")
            // min 5 days duration
            await rogueProxy.setDuration(431999)
            await expect(rogueProxy.endEpoch()).to.be.revertedWith("INFLATION_TIME_ANOMALY_ERROR")
            await rogueProxy.setDuration(432000)
            await expect(rogueProxy.endEpoch()).to.emit(rigoToken, "TokenMinted")
            await expect(rogueProxy.endEpoch()).to.be.reverted
            await timeTravel({ days: 5, mine:true })
            const mintAmount = await rogueProxy.getInflation()
            expect(await rogueProxy.callStatic.endEpoch()).to.be.eq(mintAmount)
            await expect(rogueProxy.endEpoch()).to.emit(rigoToken, "TokenMinted").withArgs(proxy.address, mintAmount)
            await expect(rogueProxy.endEpoch()).to.be.revertedWith("INFLATION_EPOCH_END_ERROR")
        })

        it('should not attach staking with invalid params', async () => {
            const { inflation, stakingProxy, rigoToken } = await setupTests()
            const StakingProxyInstance = await deployments.get("StakingProxy")
            const StakingProxy = await hre.ethers.getContractFactory("StakingProxy")
            const proxy = StakingProxy.attach(StakingProxyInstance.address)
            const source = `
            contract Staking {
                event Init(address from);
                uint256 public epochDurationInSeconds = 1 days;
                uint256 public minimumPoolStake = 1e19;
                uint32 public cobbDouglasAlphaNumerator = 2;
                uint32 public cobbDouglasAlphaDenominator = 3;
                uint32 public rewardDelegatedStakeWeight = 1e5;
                uint32 public PPM_DENOMINATOR = 1e6;
                address private inflation;
                bytes4 immutable private SELECTOR = bytes4(keccak256(bytes("mintInflation()")));
                function init() public { emit Init(msg.sender); }
                function setTarget(address _inflation) external { inflation = _inflation; }
                function endEpoch() external returns (uint256) {
                    (bool success, bytes memory data) = inflation.call(abi.encodeWithSelector(SELECTOR));
                }
                function setDuration() external { epochDurationInSeconds = 0; }
            }`
            const mockImplementation = await deployContract(user1, source)
            await mockImplementation.setTarget(inflation.address)
            await proxy.addAuthorizedAddress(user1.address)
            await expect(
                proxy.detachStakingContract()
            ).to.emit(proxy, "StakingContractDetachedFromProxy")
            // staking contract should revert on adding contract with invalid parameters
            /*await expect(
                proxy.attachStakingContract(mockImplementation.address)
            ).to.be.reverted
            */
            //await expect(stakingProxy.endEpoch()).to.be.revertedWith("STAKING_ADDRESS_NULL_ERROR")
            /*const stakingInstance = await deployments.get("Staking")
            await expect(
                proxy.attachStakingContract(stakingInstance.address)
            ).to.be.revertedWith("STAKING_SCHEDULER_ALREADY_INITIALIZED_ERROR")
            */
        })
    })

    describe("timeUntilNextClaim", async () => {
        it('should return 0 before second epoch', async () => {
            const { inflation, stakingProxy } = await setupTests()
            expect(await inflation.timeUntilNextClaim()).to.be.eq(0)
            await timeTravel({ days: 14, mine:true })
            await stakingProxy.endEpoch()
            expect(await inflation.timeUntilNextClaim()).to.be.eq(0)
        })

        it('should return positive amount after first claim, 0 after 14 days', async () => {
            const { inflation, stakingProxy } = await setupTests()
            await timeTravel({ days: 14, mine:true })
            await stakingProxy.endEpoch()
            // after first epoch end will mint for the first time
            await timeTravel({ days: 14, mine:true })
            await stakingProxy.endEpoch()
            expect(await inflation.timeUntilNextClaim()).to.be.not.eq(0)
            await timeTravel({ days: 14, mine:true })
            expect(await inflation.timeUntilNextClaim()).to.be.eq(0)
        })
    })

    describe("getEpochInflation", async () => {
        it('should return 0 before second epoch', async () => {
            const { inflation, stakingProxy } = await setupTests()
            // first epoch required to activate stake
            expect(await inflation.getEpochInflation()).to.be.eq(0)
            await timeTravel({ days: 14, mine:true })
            await stakingProxy.endEpoch()
            expect(await inflation.getEpochInflation()).to.be.eq(0)
        })

        it('should return epoch inflation after first claim', async () => {
            const { inflation, stakingProxy, rigoToken } = await setupTests()
            // first epoch finalization will not mint as no active stake would be possible
            await timeTravel({ days: 14, mine:true })
            await stakingProxy.endEpoch()
            await timeTravel({ days: 14, mine:true })
            await stakingProxy.endEpoch()
            expect(await inflation.getEpochInflation()).to.be.not.eq(0)
            const grgSupply = await rigoToken.totalSupply()
            const epochInflation = Number(grgSupply) * 2 / 100 * 14 / 365
            expect(Number(await inflation.getEpochInflation())).to.be.eq(epochInflation)
            // fixed amount per epoch regardless time of claim
            await timeTravel({ days: 7, mine:true })
            expect(Number(await inflation.getEpochInflation())).to.be.eq(epochInflation)
        })
    })
})
