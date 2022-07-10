// SPDX-License-Identifier: Apache 2.0
/*

 Copyright 2022 Rigo Intl.

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

pragma solidity 0.8.14;

import { IAuthorityCore as Authority } from "./interfaces/IAuthorityCore.sol";
import { IExchangesAuthority as ExchangesAuthority } from "./interfaces/IExchangesAuthority.sol";
import { ISigVerifier as SigVerifier } from "./interfaces/ISigVerifier.sol";
import { INavVerifier as NavVerifier } from "./interfaces/INavVerifier.sol";
import { IKyc as Kyc } from "./interfaces/IKyc.sol";
import { IERC20 as Token } from "./interfaces/IERC20.sol";
import { LibFindMethod } from "../utils/libFindMethod/LibFindMethod.sol";
import { OwnedUninitialized as Owned } from "../utils/owned/OwnedUninitialized.sol";
import { ReentrancyGuard } from "../utils/reentrancyGuard/ReentrancyGuard.sol";

import { IRigoblockV3Pool } from "./IRigoblockV3Pool.sol";

/// @title Drago - A set of rules for a drago.
/// @author Gabriele Rigo - <gab@rigoblock.com>
// solhint-disable-next-line
contract RigoblockV3Pool is Owned, ReentrancyGuard, IRigoblockV3Pool {
    // TODO: moved owned methods into rigoblock v3 subcontracts, move reentrancy guard to subcontracts.
    // TODO: move name symbol and total supply to public variables
    //  or implement functions name() symbol() (totalSupply already implemented).

    // TODO: deprecate following and use msg.sig
    //using LibFindMethod for *;

    string public constant VERSION = 'HF 3.0.1';
    // TODO: make standard ERC20 1e18
    // TODO: could rename decimals as in ERC20
    uint256 public constant BASE = 1e6; // tokens are divisible by 1 million

    /// @notice address must be updated if authority changes and implementation redeployed.
    address internal immutable AUTHORITY = address(0xcbd0e85fFd354bfB84FDAA04E8BB3E82183Cc92F);

    address internal immutable _implementation = address(this);

    address internal rigoblockDao = msg.sender; // mock address for Rigoblock Dao.
    // TODO: check if we can group multiple uint for smaller implementation bytecode
    uint256 internal ratio = 80;

    // minimum order size to avoid dust clogging things up
    uint256 internal minimumOrder = 1e15; // 1e15 = 1 finney
    uint256 internal sellPrice = 1 ether;
    uint256 internal buyPrice = 1 ether;

    mapping (address => Account) internal accounts;

    DragoData data;
    Admin admin;

    struct Receipt {
        uint256 units;
        uint32 activation;
    }

    struct Account {
        uint256 balance;
        Receipt receipt;
        mapping(address => address[]) approvedAccount;
    }

    // TODO: we removed pool id here, check if useful storing at pool creation
    struct DragoData {
        string name;
        string symbol;
        uint256 totalSupply;
        uint256 transactionFee; // in basis points 1 = 0.01%
        uint32 minPeriod;
    }

    struct Admin {
        address feeCollector;
        address kycProvider;
        bool kycEnforced;
        uint256 ratio; // ratio is 80%
    }

    modifier onlyDelegateCall() {
        if (address(this) != _implementation) {
            _;
        } else {
            revert("DELEGATECALL_REQUIREMENT_ERROR");
        }
    }

    // TODO: eliminate methods with use this modifier as we want to have least intervention policy
    //  ratio should be either stored in factory or pop should query pool locked balances
    //  min period should be owner controlled with range (i.e. 1 block to 11MM blocks, 3 weeks)
    modifier onlyDragoDao() {
        require(msg.sender == rigoblockDao);
        _;
    }

    modifier onlyUninitialized() {
        require(owner == address(0), "POOL_ALREADY_INITIALIZED_ERROR");
        _;
    }

    modifier whenApprovedExchangeOrWrapper(address _target) {
        bool approvedExchange = ExchangesAuthority(getExchangesAuthority())
            .isWhitelistedExchange(_target);
        bool approvedWrapper = ExchangesAuthority(getExchangesAuthority())
            .isWhitelistedWrapper(_target);
        require(approvedWrapper || approvedExchange);
        _;
    }

    modifier whenApprovedProxy(address _proxy) {
        bool approved = ExchangesAuthority(getExchangesAuthority())
            .isWhitelistedProxy(_proxy);
        require(approved);
        _;
    }

    modifier minimumStake(uint256 amount) {
        require (amount >= minimumOrder);
        _;
    }

    modifier hasEnough(uint256 _amount) {
        require(accounts[msg.sender].balance >= _amount);
        _;
    }

    modifier positiveAmount(uint256 _amount) {
        require(accounts[msg.sender].balance + _amount > accounts[msg.sender].balance);
        _;
    }

    modifier minimumPeriodPast() {
        require(block.timestamp >= accounts[msg.sender].receipt.activation);
        _;
    }

    modifier buyPriceHigherOrEqual(uint256 _sellPrice, uint256 _buyPrice) {
        require(_sellPrice <= _buyPrice);
        _;
    }

    modifier notPriceError(uint256 _sellPrice, uint256 _buyPrice) {
        if (_sellPrice <= sellPrice / 10 || _buyPrice >= buyPrice * 10) return;
        _;
    }

    // TODO: all methods should be onlyDelegatecall modifier limited
    // also inherited methods (owner) should be delegatecall in this context

    function _initializePool(
        string memory _poolName,
        string memory _poolSymbol,
        address _owner
    )
        onlyUninitialized // could check in fallback instead
        external
    {
        data.name = _poolName;
        data.symbol = _poolSymbol;
        owner = _owner;
        // TODO: should emit event. Check as we are already emitting event in registry
        //    where we can filter more efficiently by event and contract
    }

    /*
     * CORE FUNCTIONS
     */
    /// @dev Allows Ether to be received.
    /// @notice Used for settlements and withdrawals.
    function pay()
        external
        payable
    {
        require(msg.value != 0);
    }

    /// @dev Allows a user to buy into a drago.
    /// @return Bool the function executed correctly.
    function buyDrago()
        external
        payable
        minimumStake(msg.value)
        returns (bool)
    {
        require(buyDragoInternal(msg.sender));
        return true;
    }

    /// @dev Allows a user to buy into a drago on behalf of an address.
    /// @param _hodler Address of the target user.
    /// @return Bool the function executed correctly.
    function buyDragoOnBehalf(address _hodler)
        external
        payable
        minimumStake(msg.value)
        returns (bool)
    {
        require(buyDragoInternal(_hodler));
        return true;
    }

    /// @dev Allows a user to sell from a drago.
    /// @param _amount Number of shares to sell.
    /// @return Bool the function executed correctly.
    function sellDrago(uint256 _amount)
        external
        nonReentrant
        hasEnough(_amount)
        positiveAmount(_amount)
        minimumPeriodPast
        returns (bool)
    {
        uint256 feeDrago;
        uint256 feeDragoDao;
        uint256 netAmount;
        uint256 netRevenue;
        (feeDrago, feeDragoDao, netAmount, netRevenue) = getSaleAmounts(_amount);
        allocateSaleTokens(msg.sender, _amount, feeDrago, feeDragoDao);
        data.totalSupply = data.totalSupply - netAmount; //safeSub(data.totalSupply, netAmount);
        payable(msg.sender).transfer(netRevenue);
        emit Burn(msg.sender, address(this), _amount, netRevenue, bytes(data.name), bytes(data.symbol));
        return true;
    }

    /// @dev Allows drago owner or authority to set the price for a drago.
    /// @param _newSellPrice Price in wei.
    /// @param _newBuyPrice Price in wei.
    /// @param _signaturevaliduntilBlock Number of blocks till expiry of new data.
    /// @param _hash Bytes32 of the transaction hash.
    /// @param _signedData Bytes of extradata and signature.
    function setPrices(
        uint256 _newSellPrice,
        uint256 _newBuyPrice,
        uint256 _signaturevaliduntilBlock,
        bytes32 _hash,
        bytes calldata _signedData)
        external
        nonReentrant
        onlyOwner
        buyPriceHigherOrEqual(_newSellPrice, _newBuyPrice)
        notPriceError(_newSellPrice, _newBuyPrice)
    {
        require(
            isValidNav(
                _newSellPrice,
                _newBuyPrice,
                _signaturevaliduntilBlock,
                _hash,
                _signedData
            )
        );
        // TODO: set mid price + spread (spread only initially).  will save gas
        // when updating the prices as will only update one variable in storage.
        sellPrice = _newSellPrice;
        buyPrice = _newBuyPrice;
        emit NewNav(msg.sender, address(this), _newSellPrice, _newBuyPrice);
    }

    /// @dev Allows pool owner to change fee split ratio between fee collector and Dao.
    /// @param _ratio Number of ratio for fee collector, from 0 to 100.
    // TODO: this method should be delegated to DAO and universal for all pools.
    function changeRatio(uint256 _ratio)
        external
        onlyOwner
    {
        require(
            _ratio != uint256(0),
            "POOL_RATIO_NULL_ERROR"
        );
        ratio = _ratio;
        emit NewRatio(msg.sender, address(this), _ratio);
    }

    /// @dev Allows drago owner to set the transaction fee.
    /// @param _transactionFee Value of the transaction fee in basis points.
    function setTransactionFee(uint256 _transactionFee)
        external
        onlyOwner
    {
        require(
            _transactionFee <= 100,
            "POOL_FEE_HIGHER_THAN_ONE_PERCENT_ERROR"
            ); //fee cannot be higher than 1%
        data.transactionFee = _transactionFee;
        emit NewFee(msg.sender, address(this), _transactionFee);
    }

    /// @dev Allows owner to decide where to receive the fee.
    /// @param _feeCollector Address of the fee receiver.
    function changeFeeCollector(address _feeCollector)
        external
        onlyOwner
    {
        admin.feeCollector = _feeCollector;
        emit NewCollector(msg.sender, address(this), _feeCollector);
    }

    /// @dev Allows drago dao/factory to change the minimum holding period.
    /// @param _minPeriod Time in seconds.
    function changeMinPeriod(uint32 _minPeriod)
        external
        onlyOwner
    {
        require(
            _minPeriod <= 15 days,
            "POOL_LOCKUP_LONGER_THAN_15_DAYS_ERROR"
        );
        data.minPeriod = _minPeriod;
    }

    function enforceKyc(
        bool _enforced,
        address _kycProvider)
        external
        onlyOwner
    {
        admin.kycEnforced = _enforced;
        admin.kycProvider = _kycProvider;
    }

    /// @dev Allows owner to set an allowance to an approved token transfer proxy.
    /// @param _tokenTransferProxy Address of the proxy to be approved.
    /// @param _token Address of the token to receive allowance for.
    /// @param _amount Number of tokens approved for spending.
    // TODO: move method to faucet or change to revoke allowance only
    function setAllowance(
        address _tokenTransferProxy,
        address _token,
        uint256 _amount)
        external
        onlyOwner
        whenApprovedProxy(_tokenTransferProxy)
    {
        require(setAllowancesInternal(_tokenTransferProxy, _token, _amount));
    }

    /// @dev Allows owner to set allowances to multiple approved tokens with one call.
    /// @param _tokenTransferProxy Address of the proxy to be approved.
    /// @param _tokens Address of the token to receive allowance for.
    /// @param _amounts Array of number of tokens to be approved.
    function setMultipleAllowances(
        address _tokenTransferProxy,
        address[] calldata _tokens,
        uint256[] calldata _amounts)
        external
        onlyOwner
        whenApprovedProxy(_tokenTransferProxy)
    {
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (!setAllowancesInternal(_tokenTransferProxy, _tokens[i], _amounts[i])) continue;
        }
    }

    /// @dev Allows owner to operate on exchange through extension.
    /// @param _exchange Address of the target exchange.
    /// @param transaction ABIencoded transaction.
    function operateOnExchange(
        address _exchange,
        Transaction memory transaction)
        public
        onlyOwner
        nonReentrant
        whenApprovedExchangeOrWrapper(_exchange)
        returns (bool success)
    {
        address adapter = getExchangeAdapter(_exchange);
        bytes memory transactionData = transaction.assembledData;
        require(
            methodAllowedOnExchange(
                findMethod(transactionData),
                adapter
            )
        );

        bytes memory response;
        bool failed = true;

        assembly {

            let succeeded := delegatecall(
                sub(gas(), 5000),
                adapter,
                add(transactionData, 0x20),
                mload(transactionData),
                0,
                32) // 0x0

            // load delegatecall output
            response := mload(0)
            failed := iszero(succeeded)

            switch failed
            case 1 {
                // throw if delegatecall failed
                revert(0, 0)
            }
        }

        return (success = true);
    }

    /// @dev Allows owner or approved exchange to send a transaction to exchange
    /// @dev With data of signed/unsigned transaction
    /// @param _exchange Address of the exchange
    /// @param transactions Array of ABI encoded transactions
    function batchOperateOnExchange(
        address _exchange,
        Transaction[] memory transactions)
        external
        onlyOwner
        nonReentrant
        whenApprovedExchangeOrWrapper(_exchange)
    {
        for (uint256 i = 0; i < transactions.length; i++) {
            if (!operateOnExchange(_exchange, transactions[i])) continue;
        }
    }

    /*
     * CONSTANT PUBLIC FUNCTIONS
     */
    /// @dev Calculates how many shares a user holds.
    /// @param _who Address of the target account.
    /// @return Number of shares.
    function balanceOf(address _who)
        external
        view
        override
        returns (uint256)
    {
        return accounts[_who].balance;
    }

    /// @dev Finds details of a drago pool.
    /// @return poolName String name of a drago.
    /// @return poolSymbol String symbol of a drago.
    /// @return Value of the share price in wei.
    /// @return Value of the share price in wei.
    function getData()
        external
        view
        returns (
            string memory poolName,
            string memory poolSymbol,
            uint256,    // sellPrice
            uint256     // buyPrice
        )
    {
        return(
            poolName = data.name,
            poolSymbol = data.symbol,
            sellPrice,
            buyPrice
        );
    }

    /// @dev Returns the price of a pool.
    /// @return Value of the share price in wei.
    function calcSharePrice()
        external
        view
        returns (uint256)
    {
        return sellPrice;
    }

    /// @dev Finds the administrative data of the pool.
    /// @return Address of the owner.
    /// @return feeCollector Address of the account where a user collects fees.
    /// @return dragoDao Address of the drago dao/factory.
    /// @return ratio Number of the fee split ratio.
    /// @return transactionFee Value of the transaction fee in basis points.
    /// @return minPeriod Number of the minimum holding period for shares.
    function getAdminData()
        external
        view
        returns (
            address,  //owner
            address feeCollector,
            address,  // rigoblockDao
            uint256,  // ratio
            uint256 transactionFee,
            uint32 minPeriod
        )
    {
        return (
            owner,
            admin.feeCollector,
            rigoblockDao,
            ratio,
            data.transactionFee,
            data.minPeriod
        );
    }

    function getKycProvider()
        external
        view
        returns (address kycProviderAddress)
    {
        if(admin.kycEnforced) {
            return kycProviderAddress = admin.kycProvider;
        }
    }

    /// @dev Verifies that a signature is valid.
    /// @param hash Message hash that is signed.
    /// @param signature Proof of signing.
    /// @return isValid Validity of order signature.
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    )
        external
        view
        returns (bool isValid)
    {
        isValid = SigVerifier(getSigVerifier())
            .isValidSignature(hash, signature);
        return isValid;
    }

    /// @dev Finds the exchanges authority.
    /// @return Address of the exchanges authority.
    function getExchangesAuth()
        external
        view
        returns (address)
    {
        return getExchangesAuthority();
    }

    /// @dev Returns the total amount of issued tokens for this drago.
    /// @return Number of shares.
    function totalSupply()
        external view
        returns (uint256)
    {
        return data.totalSupply;
    }

    function name()
        external
        view
        override
        returns (string memory)
    {
        return data.name;
    }

    function symbol()
        external
        view
        override
        returns (string memory)
    {
        return data.symbol;
    }

    /*
     * NON-IMPLEMENTED INTERFACE FUNCTIONS
     */
    function transfer(
        address _to,
        uint256 _value
    )
        external
        override
        virtual
        returns (bool success)
    {}

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    )
        external
        override
        virtual
        returns (bool success)
    {}

    function approve(
        address _spender,
        uint256 _value
    )
        external
        override
        virtual
        returns (bool success)
    {}

    function allowance(
        address _owner,
        address _spender)
        external
        view
        override
        virtual
        returns (uint256)
    {}

    /*
     * INTERNAL FUNCTIONS
     */

    /// @dev Executes the pool purchase.
    /// @param _hodler Address of the target user.
    /// @return Bool the function executed correctly.
    function buyDragoInternal(address _hodler)
        internal
        returns (bool)
    {
        if (admin.kycProvider != address(0)) {
            require(Kyc(admin.kycProvider).isWhitelistedUser(_hodler));
        }
        uint256 grossAmount;
        uint256 feeDrago;
        uint256 feeDragoDao;
        uint256 amount;
        (grossAmount, feeDrago, feeDragoDao, amount) = getPurchaseAmounts();
        allocatePurchaseTokens(_hodler, amount, feeDrago, feeDragoDao);
        data.totalSupply = data.totalSupply + grossAmount;
        emit Mint(msg.sender, address(this), _hodler, msg.value, amount, bytes(data.name), bytes(data.symbol));
        return true;
    }

    /// @dev Allocates tokens to buyer, splits fee in tokens to wizard and dao.
    /// @param _hodler Address of the buyer.
    /// @param _amount Value of issued tokens.
    /// @param _feeDrago Number of shares as fee.
    /// @param _feeDragoDao Number of shares as fee to dao.
    function allocatePurchaseTokens(
        address _hodler,
        uint256 _amount,
        uint256 _feeDrago,
        uint256 _feeDragoDao)
        internal
    {
        accounts[_hodler].balance = accounts[_hodler].balance + _amount;
        if (_feeDrago != uint256(0)) {
            // TODO: test
            address feeCollector = admin.feeCollector != address(0) ? admin.feeCollector : owner;
            accounts[feeCollector].balance = accounts[feeCollector].balance + _feeDrago;
            accounts[rigoblockDao].balance = accounts[rigoblockDao].balance + _feeDragoDao;
        }
        unchecked { accounts[_hodler].receipt.activation = uint32(block.timestamp) + data.minPeriod; }
    }

    /// @dev Destroys tokens of seller, splits fee in tokens to wizard and dao.
    /// @param _hodler Address of the seller.
    /// @param _amount Value of burnt tokens.
    /// @param _feeDrago Number of shares as fee.
    /// @param _feeDragoDao Number of shares as fee to dao.
    function allocateSaleTokens(
        address _hodler,
        uint256 _amount,
        uint256 _feeDrago,
        uint256 _feeDragoDao)
        internal
    {
        accounts[_hodler].balance = accounts[_hodler].balance - _amount;
        if (_feeDrago != uint256(0)) {
            address feeCollector = admin.feeCollector != address(0) ? admin.feeCollector : owner;
            accounts[feeCollector].balance = accounts[feeCollector].balance + _feeDrago;
            accounts[rigoblockDao].balance = accounts[rigoblockDao].balance + _feeDragoDao;
        }
    }

    /// @dev Allows owner to set an infinite allowance to an approved exchange.
    /// @param _tokenTransferProxy Address of the proxy to be approved.
    /// @param _token Address of the token to receive allowance for.
    function setAllowancesInternal(
        address _tokenTransferProxy,
        address _token,
        uint256 _amount)
        internal
        returns (bool)
    {
        require(Token(_token)
            .approve(_tokenTransferProxy, _amount));
        return true;
    }

    /// @dev Calculates the correct purchase amounts.
    /// @return grossAmount Number of new shares.
    /// @return feeDrago Value of fee in shares.
    /// @return feeDragoDao Value of fee in shares to dao.
    /// @return amount Value of net purchased shares.
    function getPurchaseAmounts()
        internal
        view
        returns (
            uint256 grossAmount,
            uint256 feeDrago,
            uint256 feeDragoDao,
            uint256 amount
        )
    {
        grossAmount = msg.value * BASE / buyPrice;
        uint256 fee; // fee is in basis points

        if (data.transactionFee != uint256(0)) {
            fee = grossAmount * data.transactionFee / 10000;
            feeDrago = fee * ratio / 100;
            feeDragoDao = fee - feeDrago;
            amount = grossAmount - fee;
        } else {
            feeDrago = uint256(0);
            feeDragoDao = uint256(0);
            amount = grossAmount;
        }
    }

    /// @dev Calculates the correct sale amounts.
    /// @return feeDrago Value of fee in shares.
    /// @return feeDragoDao Value of fee in shares to dao.
    /// @return netAmount Value of net sold shares.
    /// @return netRevenue Value of sale amount for hodler.
    function getSaleAmounts(uint256 _amount)
        internal
        view
        returns (
            uint256 feeDrago,
            uint256 feeDragoDao,
            uint256 netAmount,
            uint256 netRevenue
        )
    {
        uint256 fee = _amount * data.transactionFee / 10000; //fee is in basis points
        return (
            feeDrago = fee * ratio / 100,
            feeDragoDao = fee - feeDragoDao,
            netAmount = _amount - fee,
            netRevenue = netAmount * sellPrice / BASE
        );
    }

    /// @dev Returns the address of the signature verifier.
    /// @return Address of the verifier contract.
    function getSigVerifier()
        internal
        view
        returns (address)
    {
        return ExchangesAuthority(
            Authority(AUTHORITY)
            .getExchangesAuthority())
            .getSigVerifier();
    }

    /// @dev Returns the address of the price verifier.
    /// @return Address of the verifier contract.
    function getNavVerifier()
        internal
        view
        returns (address)
    {
        return Authority(AUTHORITY)
            .getNavVerifier();
    }

    /// @dev Verifies that a signature is valid.
    /// @param _sellPrice Price in wei.
    /// @param _buyPrice Price in wei.
    /// @param _signaturevaliduntilBlock Number of blocks till price expiry.
    /// @param _hash Message hash that is signed.
    /// @param _signedData Proof of nav validity.
    /// @return isValid Bool validity of signed price update.
    function isValidNav(
        uint256 _sellPrice,
        uint256 _buyPrice,
        uint256 _signaturevaliduntilBlock,
        bytes32 _hash,
        bytes memory _signedData)
        internal
        view
        returns (bool isValid)
    {
        isValid = NavVerifier(getNavVerifier()).isValidNav(
            _sellPrice,
            _buyPrice,
            _signaturevaliduntilBlock,
            _hash,
            _signedData
        );
        return isValid;
    }

    /// @dev Finds the exchanges authority.
    /// @return Address of the exchanges authority.
    function getExchangesAuthority()
        internal
        view
        returns (address)
    {
        return Authority(AUTHORITY).getExchangesAuthority();
    }

    /// @dev Returns the address of the exchange adapter.
    /// @param _exchange Address of the target exchange.
    /// @return Address of the exchange adapter.
    function getExchangeAdapter(address _exchange)
        internal
        view
        returns (address)
    {
        return ExchangesAuthority(
            Authority(AUTHORITY)
            .getExchangesAuthority())
            .getExchangeAdapter(_exchange);
    }

    /// @dev Returns the method of a call.
    /// @param assembledData Bytes of the encoded transaction.
    /// @return method Bytes4 function signature.
    function findMethod(bytes memory assembledData)
        internal
        pure
        returns (bytes4 method)
    {
        return method = LibFindMethod.findMethod(assembledData);
    }

    /// @dev Finds if a method is allowed on an exchange.
    /// @param _adapter Address of the target exchange.
    /// @return Bool the method is allowed.
    function methodAllowedOnExchange(
        bytes4 _method,
        address _adapter)
        internal
        view
        returns (bool)
    {
        return ExchangesAuthority(
            Authority(AUTHORITY)
            .getExchangesAuthority())
            .isMethodAllowed(_method, _adapter);
    }
}
