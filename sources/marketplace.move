module collectibleswap::marketplace {
    use std::signer;
    use std::string:: {Self, String};
    use std::vector;
    use std::type_info;
    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;
    use aptos_framework::coin::{Self, Coin, BurnCapability, MintCapability, FreezeCapability};
    use aptos_std::event::{Self, EventHandle};    
    use aptos_std::table::{Self, Table};
    use std::table_with_length::{Self, TableWithLength};
    use aptos_token::token;
    use std::option::{Self, Option};
    use movemate::math;
    use movemate::u256;
    use collectibleswap::linear;
    use collectibleswap::exponential;
    use collectibleswap::emergency::assert_no_emergency;

    const ESELLER_CAN_NOT_BE_BUYER: u64 = 1;
    const FEE_DENOMINATOR: u64 = 10000;
    const FEE_DIVISOR: u64 = 10000;
    const PROTOCOL_FEE_MULTIPLIER: u64 = 100;   //1%

    const POOL_TYPE_COIN: u8 = 0;
    const POOL_TYPE_TOKEN: u8 = 1;
    const POOL_TYPE_TRADING: u8 = 2;
    const CURVE_LINEAR_TYPE: u8 = 0;
    const CURVE_EXPONENTIAL_TYPE: u8 = 1;

    //error code
    const PAIR_ALREADY_EXISTS: u64 = 1000;
    const INVALID_INPUT_TOKENS: u64 = 1001;
    const EMPTY_NFTS_INPUT: u64 = 1002;
    const PAIR_NOT_EXISTS: u64 = 1003;
    const INVALID_POOL_COLLECTION: u64 = 1004;
    const LP_MUST_GREATER_THAN_ZERO: u64 = 1005;
    const INTERNAL_ERROR_HANDLING_LIQUIDITY: u64 = 1006;
    const LIQUIDITY_VALUE_TOO_LOW: u64 = 1007;
    const INVALID_POOL_TYPE: u64 = 1008;
    const INVALID_CURVE_TYPE: u64 = 1009;
    const NUM_NFTS_MUST_GREATER_THAN_ZERO: u64 = 1010;
    const WRONG_POOL_TYPE: u64 = 1011;
    const NOT_ENOUGH_NFT_IN_POOL: u64 = 1012;
    const FAILED_TO_GET_BUY_INFO: u64 = 1013;
    const INPUT_COIN_EXCEED_COIN_AMOUNT: u64 = 1014;
    const FAILED_TO_GET_SELL_INFO: u64 = 1015;
    const INSUFFICIENT_OUTPUT_AMOUNT: u64 = 1016;
    const ERR_NOT_ENOUGH_PERMISSIONS_TO_INITIALIZE: u64 = 1017;
    const MARKET_ALREADY_INITIALIZED: u64 = 1018;

    struct Pool<phantom CoinType, phantom CollectionCoinType> has key {
        coin_amount: Coin<CoinType>,
        protocol_credit_coin: Coin<CoinType>,
        collection: String,
        collection_type: type_info::TypeInfo,
        tokens: TableWithLength<token::TokenId, token::Token>,
        token_ids_list: vector<token::TokenId>,
        mint_capability: MintCapability<LiquidityCoin<CoinType, CollectionCoinType>>,
        freeze_capability: FreezeCapability<LiquidityCoin<CoinType, CollectionCoinType>>,
        burn_capability: BurnCapability<LiquidityCoin<CoinType, CollectionCoinType
        >>,
        spot_price: u64,
        curve_type: u8,
        pool_type: u8,
        asset_recipient: address,
        delta: u64,
        fee: u64
    }

    // pool creator should create a unique CollectionCoinType for their collection, this function should be provided on
    // collectibleswap front-end
    struct LiquidityCoin<phantom CoinType, phantom CollectionCoinType> {}

    /// Stores resource account signer capability under Liquidswap account.
    struct PoolAccountCap has key { signer_cap: SignerCapability }

    /// Initializes Liquidswap contracts.
    public entry fun initialize_script(collectibleswap_admin: &signer) {
        assert!(signer::address_of(collectibleswap_admin) == @collectibleswap, ERR_NOT_ENOUGH_PERMISSIONS_TO_INITIALIZE);
        assert!(!exists<PoolAccountCap>(@collectibleswap), MARKET_ALREADY_INITIALIZED);
        let (_, signer_cap) =
            account::create_resource_account(collectibleswap_admin, b"collectibleswap_pool_resource_account");
        move_to(collectibleswap_admin, PoolAccountCap { signer_cap });
    }

    fun get_pool_account_signer(): (address, signer) acquires PoolAccountCap {
        let pool_account_cap = borrow_global<PoolAccountCap>(@collectibleswap);
        let pool_account = account::create_signer_with_capability(&pool_account_cap.signer_cap);
        return (signer::address_of(&pool_account), pool_account)
    }

    public fun create_new_pool<CoinType, CollectionCoinType>(
                    root: &signer, 
                    collection: String, 
                    token_names: &vector<String>,
                    token_creators: &vector<address>,
                    initial_spot_price: u64,
                    curve_type: u8,
                    pool_type: u8,
                    asset_recipient: address,
                    delta: u64,
                    fee: u64,
                    property_version: u64) acquires Pool, PoolAccountCap {
        // make sure pair does not exist already
        assert_no_emergency();
        let (pool_account_address, pool_account_signer) = get_pool_account_signer();
        assert!(pool_type == POOL_TYPE_TRADING || pool_type == POOL_TYPE_TOKEN || pool_type == POOL_TYPE_COIN, INVALID_POOL_TYPE);
        assert!(curve_type == CURVE_LINEAR_TYPE || curve_type == CURVE_EXPONENTIAL_TYPE, INVALID_CURVE_TYPE);
        assert!(!exists<Pool<CoinType, CollectionCoinType>>(pool_account_address), PAIR_ALREADY_EXISTS); 
        assert!(vector::length(token_names) == vector::length(token_creators), INVALID_INPUT_TOKENS);
        assert!(vector::length(token_names) > 0, EMPTY_NFTS_INPUT);
        // initialize new coin type to represent this pair's liquidity
        // coin::initialize checks that signer::address_of(root) == @aubrium so we don't have to check it here
        let (burn_capability, freeze_capability, mint_capability) = coin::initialize<LiquidityCoin<CoinType, CollectionCoinType>>(
            root,
            string::utf8(b"CollectibleSwap NFT AMM LP"),
            string::utf8(b"CSP-NFT-LP"),
            9,
            true,
        );

        // compute coin amount
        let initial_coin_amount = vector::length(token_names) * initial_spot_price;
        let c = coin::withdraw<CoinType>(root, initial_coin_amount);

        let liquidity = math::sqrt(initial_coin_amount);
        let liquidity_coin = coin::mint<LiquidityCoin<CoinType, CollectionCoinType>>(liquidity, &mint_capability);
        coin::register<LiquidityCoin<CoinType, CollectionCoinType>>(root);
        let sender = signer::address_of(root);
        coin::deposit(sender, liquidity_coin);

        // // create and store new pair
        move_to(&pool_account_signer, Pool<CoinType, CollectionCoinType> {
            coin_amount: c,
            protocol_credit_coin: coin::zero<CoinType>(),
            collection,
            collection_type: type_info::type_of<CollectionCoinType>(),
            tokens: table_with_length::new(),
            token_ids_list: vector::empty(),
            mint_capability,
            freeze_capability,
            burn_capability,
            spot_price: initial_spot_price,
            curve_type,
            pool_type,
            asset_recipient,
            delta,
            fee
        });

        internal_get_tokens_to_pool<CoinType, CollectionCoinType>(root, collection, token_names, token_creators, property_version)
    }

    fun internal_get_tokens_to_pool<CoinType, CollectionCoinType>(account: &signer, collection: String, token_names: &vector<String>, token_creators: &vector<address>, property_version: u64) acquires Pool, PoolAccountCap {
        // withdrawing tokens
        let i = 0; // define counter
        let count = vector::length(token_names);
        let (pool_account_address, _) = get_pool_account_signer();
        let pool = borrow_global_mut<Pool<CoinType, CollectionCoinType>>(pool_account_address);
        while (i < count) {
            let token_id = token::create_token_id_raw(*vector::borrow<address>(token_creators, i), collection, *vector::borrow<String>(token_names, i), property_version);
            let token = token::withdraw_token(account, token_id, 1);
            vector::push_back(&mut pool.token_ids_list, token_id);
            table_with_length::add(&mut pool.tokens, token_id, token);
            i = i + 1;
        }
    }

    public entry fun create_new_pool_script<CoinType, CollectionCoinType>(
                                    root: &signer,
                                    collection: String, 
                                    token_names: vector<String>,
                                    token_creators: vector<address>,
                                    initial_spot_price: u64,
                                    curve_type: u8,
                                    pool_type: u8,
                                    asset_recipient: address,
                                    delta: u64,
                                    fee: u64,
                                    property_version: u64) acquires Pool, PoolAccountCap {
        create_new_pool<CoinType, CollectionCoinType>(root, collection, &token_names, &token_creators, initial_spot_price, curve_type, pool_type, asset_recipient, delta, fee, property_version)
    }

    public fun add_liquidity<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    collection: String, 
                                    token_names: &vector<String>,
                                    token_creators: &vector<address>,
                                    property_version: u64) acquires Pool, PoolAccountCap {
        assert_no_emergency();
        let (pool_account_address, _) = get_pool_account_signer();
        assert!(exists<Pool<CoinType, CollectionCoinType>>(pool_account_address), PAIR_NOT_EXISTS); 
        assert!(vector::length(token_names) == vector::length(token_creators), INVALID_INPUT_TOKENS);
        assert!(vector::length(token_names) > 0, EMPTY_NFTS_INPUT);

        let pool = borrow_global_mut<Pool<CoinType, CollectionCoinType>>(pool_account_address);

        assert!(pool.collection == collection, INVALID_POOL_COLLECTION);

        // compute coin amount
        let added_token_count = vector::length(token_names);
        let coin_amount = added_token_count * pool.spot_price;
        let c = coin::withdraw<CoinType>(account, coin_amount);
        coin::merge(&mut pool.coin_amount, c);

        let current_token_count_in_pool = table_with_length::length<token::TokenId, token::Token>(&pool.tokens);
        let current_liquid_supply = option::extract<u128>(&mut coin::supply<LiquidityCoin<CoinType, CollectionCoinType>>());

        let liquidity = (current_liquid_supply as u64) * added_token_count / current_token_count_in_pool;

        let sender = signer::address_of(account);
        let liquidity_coin = coin::mint<LiquidityCoin<CoinType, CollectionCoinType>>(liquidity, &pool.mint_capability);
        if (!coin::is_account_registered<LiquidityCoin<CoinType, CollectionCoinType>>(sender)) {
            coin::register<LiquidityCoin<CoinType, CollectionCoinType>>(account);
        };
        coin::deposit(sender, liquidity_coin);

        internal_get_tokens_to_pool<CoinType, CollectionCoinType>(account, collection, token_names, token_creators, property_version)
        
    }

    public entry fun add_liquidity_script<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    collection: String, 
                                    token_names: vector<String>,
                                    token_creators: vector<address>,
                                    property_version: u64) acquires Pool, PoolAccountCap {
        add_liquidity<CoinType, CollectionCoinType>(account, collection, &token_names, &token_creators, property_version)
    }

    public fun remove_liquidity<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    collection: String, 
                                    lp_amount: u64) acquires Pool, PoolAccountCap {
        assert_no_emergency();
        let (pool_account_address, _) = get_pool_account_signer();
        assert!(exists<Pool<CoinType, CollectionCoinType>>(pool_account_address), PAIR_NOT_EXISTS); 
        assert!(lp_amount > 0, LP_MUST_GREATER_THAN_ZERO);

        let pool = borrow_global_mut<Pool<CoinType, CollectionCoinType>>(pool_account_address);

        assert!(pool.collection == collection, INVALID_POOL_COLLECTION);

        let lp_coin = coin::withdraw<LiquidityCoin<CoinType, CollectionCoinType>>(account, lp_amount);
        let lp_supply_option = coin::supply<LiquidityCoin<CoinType, CollectionCoinType>>();
        let lp_supply = (option::extract<u128>(&mut lp_supply_option) as u64);
        let current_token_count_in_pool = table_with_length::length<token::TokenId, token::Token>(&pool.tokens);
        let withdrawnable_coin_u256 = u256::mul(
                        u256::mul(u256::from_u64((current_token_count_in_pool as u64)), u256::from_u64(pool.spot_price)),
                        u256::from_u64(lp_amount)
                    );
        withdrawnable_coin_u256 = u256::div(withdrawnable_coin_u256, u256::from_u64(lp_supply));
        let withdrawnable_coin_amount = u256::as_u64(withdrawnable_coin_u256);

        let num_nfts_to_withdraw = current_token_count_in_pool * lp_amount / lp_supply;
        let value_in_fraction_nft: u64 = 0;

        if (num_nfts_to_withdraw * lp_supply != lp_amount * current_token_count_in_pool) {
            num_nfts_to_withdraw = num_nfts_to_withdraw + 1;

            // TODO: get buy info
            let new_spot_price = pool.spot_price;
            value_in_fraction_nft = (num_nfts_to_withdraw - 1) * pool.spot_price + 1 * new_spot_price;
            assert!(value_in_fraction_nft >= withdrawnable_coin_amount, INTERNAL_ERROR_HANDLING_LIQUIDITY);
            value_in_fraction_nft = value_in_fraction_nft - withdrawnable_coin_amount;
        };

        assert!(withdrawnable_coin_amount >= value_in_fraction_nft, LIQUIDITY_VALUE_TOO_LOW);
        withdrawnable_coin_amount = withdrawnable_coin_amount - value_in_fraction_nft;

        coin::burn(lp_coin, &pool.burn_capability);
        //get token id list
        let i = 0; 
        while (i < num_nfts_to_withdraw) {
            let token_id = vector::pop_back(&mut pool.token_ids_list);
            let token = table_with_length::remove<token::TokenId, token::Token>(&mut pool.tokens, token_id);
            token::deposit_token(account, token);
            i = i + 1;
        };

        let withdrawnable_coin = coin::extract<CoinType>(&mut pool.coin_amount, withdrawnable_coin_amount);
        let sender = signer::address_of(account);
        if (!coin::is_account_registered<CoinType>(sender)) {
            coin::register<CoinType>(account);
        };
        coin::deposit(sender, withdrawnable_coin);
    }

    public entry fun remove_liquidity_script<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    collection: String,
                                    lp_amount: u64) acquires Pool, PoolAccountCap {
        remove_liquidity<CoinType, CollectionCoinType>(account, collection, lp_amount)
    }

    public entry fun swap_coin_to_any_tokens_script<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    collection: String,
                                    num_nfts: u64,
                                    max_coin_amount: u64) acquires Pool, PoolAccountCap {
        swap_coin_to_any_tokens<CoinType, CollectionCoinType>(account, collection, num_nfts, max_coin_amount)
    }

    public fun swap_coin_to_any_tokens<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    collection: String,
                                    num_nfts: u64,
                                    max_coin_amount: u64) acquires Pool, PoolAccountCap {
        assert_no_emergency();
        let (pool_account_address, _) = get_pool_account_signer();
        assert!(exists<Pool<CoinType, CollectionCoinType>>(pool_account_address), PAIR_NOT_EXISTS); 
        assert!(num_nfts > 0, NUM_NFTS_MUST_GREATER_THAN_ZERO);

        let pool = borrow_global_mut<Pool<CoinType, CollectionCoinType>>(pool_account_address);

        assert!(pool.collection == collection, INVALID_POOL_COLLECTION);
        assert!(pool.pool_type == POOL_TYPE_TOKEN || pool.pool_type == POOL_TYPE_TRADING, WRONG_POOL_TYPE);

        let current_token_count_in_pool = table_with_length::length<token::TokenId, token::Token>(&pool.tokens);
        assert!(num_nfts <= current_token_count_in_pool, NOT_ENOUGH_NFT_IN_POOL);

        let (protocol_fee, input_value) = update_buy_info<CoinType, CollectionCoinType>(pool, num_nfts, max_coin_amount, PROTOCOL_FEE_MULTIPLIER);

        // send tokens to buyer
        let i = 0; 
        while (i < num_nfts) {
            let token_id = vector::pop_back(&mut pool.token_ids_list);
            let token = table_with_length::remove<token::TokenId, token::Token>(&mut pool.tokens, token_id);
            token::deposit_token(account, token);
            i = i + 1;
        };

        // get coin from buyer
        let input_coin = coin::withdraw<CoinType>(account, input_value);
        let protocol_fee_coin = coin::extract<CoinType>(&mut input_coin, protocol_fee);
        coin::merge<CoinType>(&mut pool.protocol_credit_coin, protocol_fee_coin);

        // adjust pool coin amount
        if (pool.pool_type == POOL_TYPE_TRADING) {
            //trade pool, add the coin input to the pool balance
            coin::merge<CoinType>(&mut pool.coin_amount, input_coin);
        } else {
            // send coin to asset_recipient
            let sender = signer::address_of(account);
            coin::deposit(sender, input_coin);
        };
    }

    public entry fun swap_coin_to_specific_tokens<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    collection: String,
                                    token_names: vector<String>,
                                    token_creators: vector<address>,
                                    property_version: u64,
                                    max_coin_amount: u64) acquires Pool, PoolAccountCap
                                     {
        swap_coin_to_specific<CoinType, CollectionCoinType>(account, collection, &token_names, &token_creators, property_version, max_coin_amount)
    }

    public fun swap_coin_to_specific<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    collection: String,
                                    token_names: &vector<String>,
                                    token_creators: &vector<address>,
                                    property_version: u64,
                                    max_coin_amount: u64) acquires Pool, PoolAccountCap {
        assert_no_emergency();
        let (pool_account_address, _) = get_pool_account_signer();
        assert!(exists<Pool<CoinType, CollectionCoinType>>(pool_account_address), PAIR_NOT_EXISTS); 
        assert!(vector::length(token_names) == vector::length(token_creators), INVALID_INPUT_TOKENS);
        let num_nfts = vector::length(token_names);
        assert!(num_nfts > 0, NUM_NFTS_MUST_GREATER_THAN_ZERO);

        let pool = borrow_global_mut<Pool<CoinType, CollectionCoinType>>(pool_account_address);

        assert!(pool.collection == collection, INVALID_POOL_COLLECTION);
        assert!(pool.pool_type == POOL_TYPE_TOKEN || pool.pool_type == POOL_TYPE_TRADING, WRONG_POOL_TYPE);

        let current_token_count_in_pool = table_with_length::length<token::TokenId, token::Token>(&pool.tokens);
        assert!(num_nfts <= current_token_count_in_pool, NOT_ENOUGH_NFT_IN_POOL);

        let (protocol_fee, input_value) = update_buy_info<CoinType, CollectionCoinType>(pool, num_nfts, max_coin_amount, PROTOCOL_FEE_MULTIPLIER);

        // send tokens to buyer
        let i = 0; 
        while (i < num_nfts) {
            let token_id = token::create_token_id_raw(*vector::borrow<address>(token_creators, i), collection, *vector::borrow<String>(token_names, i), property_version);
            let token = table_with_length::remove<token::TokenId, token::Token>(&mut pool.tokens, token_id);
            // removing token_id from token_ids_list
            let j = 0;
            let token_ids_count_in_list = vector::length(&pool.token_ids_list);
            while (j < token_ids_count_in_list) {
                let item = vector::borrow(&mut pool.token_ids_list, j);
                if (*item == token_id) {
                    if (j == token_ids_count_in_list - 1) {
                        vector::pop_back(&mut pool.token_ids_list);
                    } else {
                        let last = vector::pop_back(&mut pool.token_ids_list);
                        let element_at_deleted_position = vector::borrow_mut(&mut pool.token_ids_list, j);
                        *element_at_deleted_position = last;
                    };
                    break

                };
                j = j + 1;
            };
            token::deposit_token(account, token);
            i = i + 1;
        };

        // get coin from buyer
        let input_coin = coin::withdraw<CoinType>(account, input_value);
        let protocol_fee_coin = coin::extract<CoinType>(&mut input_coin, protocol_fee);
        coin::merge<CoinType>(&mut pool.protocol_credit_coin, protocol_fee_coin);

        // adjust pool coin amount
        if (pool.pool_type == POOL_TYPE_TRADING) {
            //trade pool, add the coin input to the pool balance
            coin::merge<CoinType>(&mut pool.coin_amount, input_coin);
        } else {
            // send coin to asset_recipient
            let sender = signer::address_of(account);
            coin::deposit(sender, input_coin);
        };
    }

    public entry fun swap_tokens_to_coin_script<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    collection: String,
                                    token_names: vector<String>,
                                    token_creators: vector<address>,
                                    min_coin_output: u64,
                                    property_version: u64) {
        swap_tokens_to_coin<CoinType, CollectionCoinType>(account, collection, &token_names, &token_creators, min_coin_output, property_version);
    }

    public fun swap_tokens_to_coin<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    collection: String,
                                    token_names: &vector<String>,
                                    token_creators: &vector<address>,
                                    min_coin_output: u64,
                                    property_version: u64) {
        assert_no_emergency();
        // TODO
    }


    fun update_buy_info<CoinType, CollectionCoinType>(
                pool: &mut Pool<CoinType, CollectionCoinType>, 
                num_nfts: u64, 
                max_coin_amount: u64, 
                protocol_fee_multiplier: u64): (u64, u64) {
        let (error_code, new_spot_price, new_delta, input_value, protocol_fee) = get_buy_info(pool.curve_type, pool.spot_price, pool.delta, num_nfts, pool.fee, protocol_fee_multiplier);
        assert!(error_code == 0, FAILED_TO_GET_BUY_INFO);
        assert!(input_value <= max_coin_amount, INPUT_COIN_EXCEED_COIN_AMOUNT);
        pool.spot_price = new_spot_price;
        pool.delta = new_delta;
        (protocol_fee, input_value)
    }

    public fun calculate_buy_info<CoinType, CollectionCoinType>(
                num_nfts: u64, 
                max_coin_amount: u64): (u64, u64, u64, u64) acquires Pool, PoolAccountCap {
        let (pool_account_address, _) = get_pool_account_signer();
        let pool = borrow_global<Pool<CoinType, CollectionCoinType>>(pool_account_address);
        let (error_code, new_spot_price, new_delta, input_value, protocol_fee) = get_buy_info(pool.curve_type, pool.spot_price, pool.delta, num_nfts, pool.fee, PROTOCOL_FEE_MULTIPLIER);
        assert!(error_code == 0, FAILED_TO_GET_BUY_INFO);
        assert!(input_value <= max_coin_amount, INPUT_COIN_EXCEED_COIN_AMOUNT);
        (new_spot_price, new_delta, protocol_fee, input_value)
    }

    fun update_sell_info<CoinType, CollectionCoinType>(
                pool: &mut Pool<CoinType, CollectionCoinType>, 
                num_nfts: u64, 
                min_expected_coin_output: u64, 
                protocol_fee_multiplier: u64): (u64, u64) {
        let (error_code, new_spot_price, new_delta, output_value, protocol_fee) = get_sell_info(pool.curve_type, pool.spot_price, pool.delta, num_nfts, pool.fee, protocol_fee_multiplier);
        assert!(error_code == 0, FAILED_TO_GET_SELL_INFO);
        assert!(output_value >= min_expected_coin_output, INSUFFICIENT_OUTPUT_AMOUNT);
        pool.spot_price = new_spot_price;
        pool.delta = new_delta;
        (protocol_fee, output_value)
    }

    public fun calculate_sell_info<CoinType, CollectionCoinType>(
                num_nfts: u64, 
                min_expected_coin_output: u64): (u64, u64, u64, u64) acquires Pool, PoolAccountCap
                 {
        let (pool_account_address, _) = get_pool_account_signer();
        let pool = borrow_global<Pool<CoinType, CollectionCoinType>>(pool_account_address);
        let (error_code, new_spot_price, new_delta, output_value, protocol_fee) = get_sell_info(pool.curve_type, pool.spot_price, pool.delta, num_nfts, pool.fee, PROTOCOL_FEE_MULTIPLIER);
        assert!(error_code == 0, FAILED_TO_GET_SELL_INFO);
        assert!(output_value >= min_expected_coin_output, INSUFFICIENT_OUTPUT_AMOUNT);
        (new_spot_price, new_delta, protocol_fee, output_value)
    }

    fun get_buy_info(curve_type: u8, 
                    spot_price: u64,
                    delta: u64,
                    num_items: u64,
                    fee_multiplier: u64,
                    protocol_fee_multiplier: u64): (u8, u64, u64, u64, u64) {
        assert!(curve_type == CURVE_LINEAR_TYPE || curve_type == CURVE_EXPONENTIAL_TYPE, INVALID_CURVE_TYPE);
        if (curve_type == CURVE_LINEAR_TYPE) {
            linear::get_buy_info(spot_price, delta, num_items, fee_multiplier, protocol_fee_multiplier)
        } else {
            exponential::get_buy_info(spot_price, delta, num_items, fee_multiplier, protocol_fee_multiplier)
        } 
    }

    fun get_sell_info(
                    curve_type: u8,
                    spot_price: u64,
                    delta: u64,
                    num_items: u64,
                    fee_multiplier: u64,
                    protocol_fee_multiplier: u64): (u8, u64, u64, u64, u64) {
        assert!(curve_type == CURVE_LINEAR_TYPE || curve_type == CURVE_EXPONENTIAL_TYPE, INVALID_CURVE_TYPE);
        if (curve_type == CURVE_LINEAR_TYPE) {
            linear::get_sell_info(spot_price, delta, num_items, fee_multiplier, protocol_fee_multiplier)
        } else {
            exponential::get_sell_info(spot_price, delta, num_items, fee_multiplier, protocol_fee_multiplier)
        } 
    }
}