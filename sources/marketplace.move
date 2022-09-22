module collectibleswap::marketplace {
    use std::signer;
    use std::string;
    use std::vector;
    use std::string::String;
    use aptos_framework::guid;
    use aptos_framework::coin::{Self, Coin, BurnCapability, MintCapability, FreezeCapability};
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_std::event::{Self, EventHandle};    
    use aptos_std::table::{Self, Table};
    use std::table_with_length::{Self, TableWithLength};
    use aptos_token::token;
    use aptos_token::token_coin_swap::{ list_token_for_swap, exchange_coin_for_token };
    use std::option::Option;
    use std::option;
    use movemate::math;
    use movemate::u256;
    use collectibleswap::linear;
    use collectibleswap::exponential;

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

    struct Pool<phantom CoinType> has key {
        coin_amount: Coin<CoinType>,
        protocol_credit_coin: Coin<CoinType>,
        collection: String,
        tokens: TableWithLength<token::TokenId, token::Token>,
        token_ids_list: vector<token::TokenId>,
        mint_capability: MintCapability<LiquidityCoin<CoinType>>,
        freeze_capability: FreezeCapability<LiquidityCoin<CoinType>>,
        burn_capability: BurnCapability<LiquidityCoin<CoinType>>,
        spot_price: u64,
        curve_type: u8,
        pool_type: u8,
        asset_recipient: address,
        delta: u64,
        fee: u64
    }

    struct LiquidityCoin<phantom CoinType> {}

    public fun create_new_pool<CoinType>(
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
                    property_version: u64) acquires Pool {
        // make sure pair does not exist already
        assert!(pool_type == POOL_TYPE_TRADING || pool_type == POOL_TYPE_TOKEN || pool_type == POOL_TYPE_COIN, INVALID_POOL_TYPE);
        assert!(curve_type == CURVE_LINEAR_TYPE || curve_type == CURVE_EXPONENTIAL_TYPE, INVALID_CURVE_TYPE);
        assert!(!exists<Pool<CoinType>>(@collectibleswap), PAIR_ALREADY_EXISTS); 
        assert!(vector::length(token_names) == vector::length(token_creators), INVALID_INPUT_TOKENS);
        assert!(vector::length(token_names) > 0, EMPTY_NFTS_INPUT);
        // initialize new coin type to represent this pair's liquidity
        // coin::initialize checks that signer::address_of(root) == @aubrium so we don't have to check it here
        let (burn_capability, freeze_capability, mint_capability) = coin::initialize<LiquidityCoin<CoinType>>(
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
        let liquidity_coin = coin::mint<LiquidityCoin<CoinType>>(liquidity, &mint_capability);
        coin::register<LiquidityCoin<CoinType>>(root);
        let sender = signer::address_of(root);
        coin::deposit(sender, liquidity_coin);

        // // create and store new pair
        move_to(root, Pool<CoinType> {
            coin_amount: c,
            protocol_credit_coin: coin::zero<CoinType>(),
            collection,
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

        internal_get_tokens_to_pool<CoinType>(root, collection, token_names, token_creators, property_version)
    }

    fun internal_get_tokens_to_pool<CoinType>(account: &signer, collection: String, token_names: &vector<String>, token_creators: &vector<address>, property_version: u64) acquires Pool {
        // withdrawing tokens
        let i = 0; // define counter
        let count = vector::length(token_names);
        let pool = borrow_global_mut<Pool<CoinType>>(@collectibleswap);
        while (i < count) {
            let token_id = token::create_token_id_raw(*vector::borrow<address>(token_creators, i), collection, *vector::borrow<String>(token_names, i), property_version);
            let token = token::withdraw_token(account, token_id, 1);
            vector::push_back(&mut pool.token_ids_list, token_id);
            table_with_length::add(&mut pool.tokens, token_id, token);
            i = i + 1;
        }
    }

    public entry fun create_new_pool_script<CoinType>(
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
                                    property_version: u64) acquires Pool {
        create_new_pool<CoinType>(root, collection, &token_names, &token_creators, initial_spot_price, curve_type, pool_type, asset_recipient, delta, fee, property_version)
    }

    public fun add_liquidity<CoinType> (
                                    account: &signer,
                                    collection: String, 
                                    token_names: &vector<String>,
                                    token_creators: &vector<address>,
                                    property_version: u64) acquires Pool {
        assert!(exists<Pool<CoinType>>(@collectibleswap), PAIR_NOT_EXISTS); 
        assert!(vector::length(token_names) == vector::length(token_creators), INVALID_INPUT_TOKENS);
        assert!(vector::length(token_names) > 0, EMPTY_NFTS_INPUT);

        let pool = borrow_global_mut<Pool<CoinType>>(@collectibleswap);

        assert!(pool.collection == collection, INVALID_POOL_COLLECTION);

        // compute coin amount
        let added_token_count = vector::length(token_names);
        let coin_amount = added_token_count * pool.spot_price;
        let c = coin::withdraw<CoinType>(account, coin_amount);
        coin::merge(&mut pool.coin_amount, c);

        let current_token_count_in_pool = table_with_length::length<token::TokenId, token::Token>(&pool.tokens);
        let current_liquid_supply = option::extract<u128>(&mut coin::supply<CoinType>());

        let liquidity = (current_liquid_supply as u64) * added_token_count / current_token_count_in_pool;

        let sender = signer::address_of(account);
        let liquidity_coin = coin::mint<LiquidityCoin<CoinType>>(liquidity, &pool.mint_capability);
        if (!coin::is_account_registered<LiquidityCoin<CoinType>>(sender)) {
            coin::register<LiquidityCoin<CoinType>>(account);
        };
        coin::deposit(sender, liquidity_coin);

        internal_get_tokens_to_pool<CoinType>(account, collection, token_names, token_creators, property_version)
        
    }

    public entry fun add_liquidity_script<CoinType> (
                                    account: &signer,
                                    collection: String, 
                                    token_names: vector<String>,
                                    token_creators: vector<address>,
                                    property_version: u64) acquires Pool {
        add_liquidity<CoinType>(account, collection, &token_names, &token_creators, property_version)
    }

    public fun remove_liquidity<CoinType> (
                                    account: &signer,
                                    collection: String, 
                                    lp_amount: u64) acquires Pool {
        assert!(exists<Pool<CoinType>>(@collectibleswap), PAIR_NOT_EXISTS); 
        assert!(lp_amount > 0, LP_MUST_GREATER_THAN_ZERO);

        let pool = borrow_global_mut<Pool<CoinType>>(@collectibleswap);

        assert!(pool.collection == collection, INVALID_POOL_COLLECTION);

        let lp_coin = coin::withdraw<LiquidityCoin<CoinType>>(account, lp_amount);
        let lp_supply_option = coin::supply<LiquidityCoin<CoinType>>();
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

    public entry fun remove_liquidity_script<CoinType> (
                                    account: &signer,
                                    collection: String,
                                    lp_amount: u64) acquires Pool {
        remove_liquidity<CoinType>(account, collection, lp_amount)
    }

    public entry fun swap_coin_to_any_tokens_script<CoinType> (
                                    account: &signer,
                                    collection: String,
                                    num_nfts: u64,
                                    max_coin_amount: u64) acquires Pool {
        swap_coin_to_any_tokens<CoinType>(account, collection, num_nfts, max_coin_amount)
    }

    public fun swap_coin_to_any_tokens<CoinType> (
                                    account: &signer,
                                    collection: String,
                                    num_nfts: u64,
                                    max_coin_amount: u64) acquires Pool {
        assert!(exists<Pool<CoinType>>(@collectibleswap), PAIR_NOT_EXISTS); 
        assert!(num_nfts > 0, NUM_NFTS_MUST_GREATER_THAN_ZERO);

        let pool = borrow_global_mut<Pool<CoinType>>(@collectibleswap);

        assert!(pool.collection == collection, INVALID_POOL_COLLECTION);
        assert!(pool.pool_type == POOL_TYPE_TOKEN || pool.pool_type == POOL_TYPE_TRADING, WRONG_POOL_TYPE);

        let current_token_count_in_pool = table_with_length::length<token::TokenId, token::Token>(&pool.tokens);
        assert!(num_nfts <= current_token_count_in_pool, NOT_ENOUGH_NFT_IN_POOL);

        let (protocol_fee, input_value) = calculate_buy_info<CoinType>(pool, num_nfts, max_coin_amount, PROTOCOL_FEE_MULTIPLIER);

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

    public entry fun swap_coin_to_specific_tokens<CoinType> (
                                    account: &signer,
                                    collection: String,
                                    token_names: vector<String>,
                                    token_creators: vector<address>,
                                    property_version: u64,
                                    max_coin_amount: u64) acquires Pool {
        swap_coin_to_specific<CoinType>(account, collection, &token_names, &token_creators, property_version, max_coin_amount)
    }

    public fun swap_coin_to_specific<CoinType> (
                                    account: &signer,
                                    collection: String,
                                    token_names: &vector<String>,
                                    token_creators: &vector<address>,
                                    property_version: u64,
                                    max_coin_amount: u64) acquires Pool {
        assert!(exists<Pool<CoinType>>(@collectibleswap), PAIR_NOT_EXISTS); 
        assert!(vector::length(token_names) == vector::length(token_creators), INVALID_INPUT_TOKENS);
        let num_nfts = vector::length(token_names);
        assert!(num_nfts > 0, NUM_NFTS_MUST_GREATER_THAN_ZERO);

        let pool = borrow_global_mut<Pool<CoinType>>(@collectibleswap);

        assert!(pool.collection == collection, INVALID_POOL_COLLECTION);
        assert!(pool.pool_type == POOL_TYPE_TOKEN || pool.pool_type == POOL_TYPE_TRADING, WRONG_POOL_TYPE);

        let current_token_count_in_pool = table_with_length::length<token::TokenId, token::Token>(&pool.tokens);
        assert!(num_nfts <= current_token_count_in_pool, NOT_ENOUGH_NFT_IN_POOL);

        let (protocol_fee, input_value) = calculate_buy_info<CoinType>(pool, num_nfts, max_coin_amount, PROTOCOL_FEE_MULTIPLIER);

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
                    break;
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

    public entry fun swap_tokens_to_coin_script<CoinType> (
                                    account: &signer,
                                    collection: String,
                                    token_names: vector<String>,
                                    token_creators: vector<address>,
                                    min_coin_output: u64,
                                    property_version: u64) {
        swap_tokens_to_coin<CoinType>(account, collection, &token_names, &token_creators, min_coin_output, property_version);
    }

    public fun swap_tokens_to_coin<CoinType> (
                                    account: &signer,
                                    collection: String,
                                    token_names: &vector<String>,
                                    token_creators: &vector<address>,
                                    min_coin_output: u64,
                                    property_version: u64) {
        
    }


    fun calculate_buy_info<CoinType>(
                pool: &mut Pool<CoinType>, 
                num_nfts: u64, 
                max_coin_amount: u64, 
                protocol_fee_multiplier: u64): (u64, u64) {
        let current_spot_price = pool.spot_price;
        let current_delta = pool.delta;
        let (error_code, new_spot_price, new_delta, input_value, protocol_fee) = get_buy_info(pool.curve_type, pool.spot_price, pool.delta, num_nfts, pool.fee, PROTOCOL_FEE_MULTIPLIER);
        assert!(error_code == 0, FAILED_TO_GET_BUY_INFO);
        assert!(input_value <= max_coin_amount, INPUT_COIN_EXCEED_COIN_AMOUNT);
        pool.spot_price = new_spot_price;
        pool.delta = new_delta;
        (protocol_fee, input_value)
    }

    fun calculate_sell_info<CoinType>(
                pool: &mut Pool<CoinType>, 
                num_nfts: u64, 
                min_expected_coin_output: u64, 
                protocol_fee_multiplier: u64): (u64, u64) {
        let current_spot_price = pool.spot_price;
        let current_delta = pool.delta;
        let (error_code, new_spot_price, new_delta, output_value, protocol_fee) = get_sell_info(pool.curve_type, pool.spot_price, pool.delta, num_nfts, pool.fee, PROTOCOL_FEE_MULTIPLIER);
        assert!(error_code == 0, FAILED_TO_GET_SELL_INFO);
        assert!(output_value >= min_expected_coin_output, INSUFFICIENT_OUTPUT_AMOUNT);
        pool.spot_price = new_spot_price;
        pool.delta = new_delta;
        (protocol_fee, output_value)
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