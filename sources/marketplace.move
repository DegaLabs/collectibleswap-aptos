module collectibleswap::marketplace {
    use std::signer;
    use std::string:: {Self, String};
    use std::vector;
    use std::timestamp;
    use std::type_info;
    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;
    use aptos_framework::coin::{Self, Coin, BurnCapability, MintCapability, FreezeCapability};
    use aptos_std::event;    
    use aptos_std::table;
    use std::table_with_length::{Self, TableWithLength};
    use aptos_token::token;
    use std::option;
    use movemate::math;
    use movemate::u256;
    use collectibleswap::linear;
    use collectibleswap::exponential;
    use collectibleswap::emergency::assert_no_emergency;
    use collectibleswap::collectiontyperegistry::assert_valid_cointype;

    const MAX_U64: u128 = 18446744073709551615;

    /// Maximum of u128 number.
    const MAX_U128: u128 = 340282366920938463463374607431768211455;

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
    const EXCEED_MAX_COIN: u64 = 1019;
    const INSUFFICIENT_NFTS: u64 = 1020;

    struct Pool<phantom CoinType, phantom CollectionCoinType> has key {
        reserve: Coin<CoinType>,
        protocol_credit_coin: Coin<CoinType>,
        collection: String,
        token_creator: address,
        collection_type: type_info::TypeInfo,
        tokens: TableWithLength<token::TokenId, token::Token>,
        token_ids_list: vector<token::TokenId>,
        tokens_for_asset_recipient: TableWithLength<token::TokenId, token::Token>,
        token_ids_list_asset_recipient: vector<token::TokenId>,
        mint_capability: MintCapability<LiquidityCoin<CoinType, CollectionCoinType>>,
        freeze_capability: FreezeCapability<LiquidityCoin<CoinType, CollectionCoinType>>,
        burn_capability: BurnCapability<LiquidityCoin<CoinType, CollectionCoinType>>,
        spot_price: u64,
        curve_type: u8,
        pool_type: u8,
        asset_recipient: address,
        delta: u64,
        fee: u64,
        last_price_cumulative: u128,
        last_block_timestamp: u64
    }

    // Events
    struct EventsStore<phantom CoinType, phantom CollectionCoinType> has key {
        pool_created_handle: event::EventHandle<PoolCreatedEvent<CoinType, CollectionCoinType>>,
        liquidity_added_handle: event::EventHandle<LiquidityAddedEvent<CoinType, CollectionCoinType>>,
        liquidity_removed_handle: event::EventHandle<LiquidityRemovedEvent<CoinType, CollectionCoinType>>,
        swap_tokens_to_coin_handle: event::EventHandle<SwapTokensToCoinEvent<CoinType, CollectionCoinType>>,
        swap_coin_to_tokens_handle: event::EventHandle<SwapCoinToTokensEvent<CoinType, CollectionCoinType>>,
        claim_tokens_handle: event::EventHandle<ClaimTokensEvent<CoinType, CollectionCoinType>>,
        oracle_updated_handle: event::EventHandle<OracleUpdatedEvent<CoinType, CollectionCoinType>>
    }

    struct PoolCreatedEvent<phantom CoinType, phantom CollectionCoinType> has store, drop {
        collection: String,
        token_creator: address,
        curve_type: u8,
        pool_type: u8,
        spot_price: u64,
        asset_recipient: address,
        delta: u64,
        fee: u64,
        pool_creator: address,
        timestamp: u64
    }

    struct LiquidityAddedEvent<phantom CoinType, phantom CollectionCoinType> has store, drop {
        collection: String,
        token_creator: address,
        token_ids: vector<token::TokenId>,
        coin_amount: u64,
        lp_amount: u64,
        timestamp: u64
    }

    struct LiquidityRemovedEvent<phantom CoinType, phantom CollectionCoinType> has store, drop {
        collection: String,
        token_creator: address,
        token_ids: vector<token::TokenId>,
        coin_amount: u64,
        lp_amount: u64,
        timestamp: u64
    }

    struct SwapCoinToTokensEvent<phantom CoinType, phantom CollectionCoinType> has store, drop {
        collection: String,
        token_creator: address,
        token_ids: vector<token::TokenId>,
        coin_amount: u64,
        new_spot_price: u64,
        timestamp: u64
    }

    struct SwapTokensToCoinEvent<phantom CoinType, phantom CollectionCoinType> has store, drop {
        collection: String,
        token_creator: address,
        token_ids: vector<token::TokenId>,
        coin_amount: u64,
        new_spot_price: u64,
        timestamp: u64
    }

    struct ClaimTokensEvent<phantom CoinType, phantom CollectionCoinType> has store, drop {
        collection: String,
        token_creator: address,
        token_ids: vector<token::TokenId>,
        asset_recipient: address,
        timestamp: u64
    }

    struct OracleUpdatedEvent<phantom CoinType, phantom CollectionCoinType> has store, drop {
        last_price_cumulative: u128,
        timestamp: u64
    }

    // pool creator should create a unique CollectionCoinType for their collection, this function should be provided on
    // collectibleswap front-end
    struct LiquidityCoin<phantom CoinType, phantom CollectionCoinType> {}

    /// Stores resource account signer capability under Liquidswap account.
    struct PoolAccountCap has key { signer_cap: SignerCapability }

    /// Initializes CollectibleSwap resource account
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
                    account: &signer, 
                    collection: String, 
                    token_names: &vector<String>,
                    token_creator: address,
                    initial_spot_price: u64,
                    curve_type: u8,
                    pool_type: u8,
                    asset_recipient: address,
                    delta: u64,
                    fee: u64,
                    property_version: u64) acquires Pool, PoolAccountCap {
        // make sure pair does not exist already
        assert_no_emergency();
        assert_valid_cointype<CollectionCoinType>(collection, token_creator);
        let (pool_account_address, pool_account_signer) = get_pool_account_signer();
        assert!(pool_type == POOL_TYPE_TRADING || pool_type == POOL_TYPE_TOKEN || pool_type == POOL_TYPE_COIN, INVALID_POOL_TYPE);
        assert!(curve_type == CURVE_LINEAR_TYPE || curve_type == CURVE_EXPONENTIAL_TYPE, INVALID_CURVE_TYPE);
        assert!(!exists<Pool<CoinType, CollectionCoinType>>(pool_account_address), PAIR_ALREADY_EXISTS); 
        assert!(vector::length(token_names) > 0, EMPTY_NFTS_INPUT);
        // initialize new coin type to represent this pair's liquidity
        let (burn_capability, freeze_capability, mint_capability) = coin::initialize<LiquidityCoin<CoinType, CollectionCoinType>>(
            &pool_account_signer,
            string::utf8(b"CollectibleSwap NFT AMM LP"),
            string::utf8(b"CSP-NFT-LP"),
            9,
            true,
        );

        // compute coin amount
        let initial_coin_amount = vector::length(token_names) * initial_spot_price;
        let c = coin::withdraw<CoinType>(account, initial_coin_amount);

        let liquidity = math::sqrt(initial_coin_amount);
        let liquidity_coin = coin::mint<LiquidityCoin<CoinType, CollectionCoinType>>(liquidity, &mint_capability);
        let sender = signer::address_of(account);
        if (coin::is_account_registered<LiquidityCoin<CoinType, CollectionCoinType>>(sender)) {
            coin::register<LiquidityCoin<CoinType, CollectionCoinType>>(account);
        };
        coin::deposit(sender, liquidity_coin);

        // // create and store new pair
        move_to(&pool_account_signer, Pool<CoinType, CollectionCoinType> {
            reserve: c,
            protocol_credit_coin: coin::zero<CoinType>(),
            collection,
            token_creator,
            collection_type: type_info::type_of<CollectionCoinType>(),
            tokens: table_with_length::new(),
            token_ids_list: vector::empty(),
            tokens_for_asset_recipient: table_with_length::new(),
            token_ids_list_asset_recipient: vector::empty(),
            mint_capability,
            freeze_capability,
            burn_capability,
            spot_price: initial_spot_price,
            curve_type,
            pool_type,
            asset_recipient,
            delta,
            fee,
            last_price_cumulative: 0,
            last_block_timestamp: timestamp::now_seconds()
        });

        let pool = borrow_global_mut<Pool<CoinType, CollectionCoinType>>(pool_account_address);

        let token_ids = internal_get_tokens_to_pool<CoinType, CollectionCoinType>(account, pool, collection, token_names, token_creator, property_version);

        let events_store = EventsStore<CoinType, CollectionCoinType> {
            pool_created_handle: account::new_event_handle<PoolCreatedEvent<CoinType, CollectionCoinType>>(&pool_account_signer),
            liquidity_added_handle: account::new_event_handle<LiquidityAddedEvent<CoinType, CollectionCoinType>>(&pool_account_signer),
            liquidity_removed_handle: account::new_event_handle<LiquidityRemovedEvent<CoinType, CollectionCoinType>>(&pool_account_signer),
            swap_tokens_to_coin_handle: account::new_event_handle<SwapTokensToCoinEvent<CoinType, CollectionCoinType>>(&pool_account_signer),
            swap_coin_to_tokens_handle: account::new_event_handle<SwapCoinToTokensEvent<CoinType, CollectionCoinType>>(&pool_account_signer),
            claim_tokens_handle: account::new_event_handle<ClaimTokensEvent<CoinType, CollectionCoinType>>(&pool_account_signer),
            oracle_updated_handle: account::new_event_handle<OracleUpdatedEvent<CoinType, CollectionCoinType>>(&pool_account_signer)
        };
        event::emit_event(
            &mut events_store.pool_created_handle,
            PoolCreatedEvent<CoinType, CollectionCoinType> {
                collection: collection,
                token_creator: token_creator,
                curve_type: curve_type,
                pool_type: pool_type,
                spot_price: initial_spot_price,
                asset_recipient: asset_recipient,
                delta: delta,
                fee: fee,
                pool_creator: sender,
                timestamp: timestamp::now_seconds()
            },
        );

        event::emit_event(
            &mut events_store.liquidity_added_handle,
            LiquidityAddedEvent<CoinType, CollectionCoinType> {
                collection: collection,
                token_creator: token_creator,
                token_ids: token_ids,
                coin_amount: initial_coin_amount,
                lp_amount: liquidity,
                timestamp: timestamp::now_seconds()
            }
        );
        move_to(&pool_account_signer, events_store)
    }

    fun internal_get_tokens_to_pool<CoinType, CollectionCoinType>(
                                account: &signer, 
                                pool: &mut Pool<CoinType, CollectionCoinType>, 
                                collection: String, 
                                token_names: &vector<String>, 
                                token_creator: address, 
                                property_version: u64): vector<token::TokenId> {
        // withdrawing tokens
        let i = 0; // define counter
        let count = vector::length(token_names);
        let token_ids = vector::empty<token::TokenId>();
        while (i < count) {
            let token_id = token::create_token_id_raw(token_creator, collection, *vector::borrow<String>(token_names, i), property_version);
            vector::push_back<token::TokenId>(&mut token_ids, token_id);
            let token = token::withdraw_token(account, token_id, 1);
            vector::push_back(&mut pool.token_ids_list, token_id);
            table_with_length::add(&mut pool.tokens, token_id, token);
            i = i + 1;
        };
        return token_ids
    }


    public entry fun create_new_pool_script<CoinType, CollectionCoinType>(
                                    account: &signer,
                                    collection: String, 
                                    token_names: vector<String>,
                                    token_creator: address,
                                    initial_spot_price: u64,
                                    curve_type: u8,
                                    pool_type: u8,
                                    asset_recipient: address,
                                    delta: u64,
                                    fee: u64,
                                    property_version: u64) acquires Pool, PoolAccountCap {
        create_new_pool<CoinType, CollectionCoinType>(account, collection, &token_names, token_creator, initial_spot_price, curve_type, pool_type, asset_recipient, delta, fee, property_version)
    }

    public fun add_liquidity<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    max_coin_amount: u64,
                                    token_names: &vector<String>,
                                    property_version: u64) acquires Pool, PoolAccountCap, EventsStore
                                    {
        assert_no_emergency();
        let (pool_account_address, _) = get_pool_account_signer();
        assert!(exists<Pool<CoinType, CollectionCoinType>>(pool_account_address), PAIR_NOT_EXISTS); 
        let pool = borrow_global_mut<Pool<CoinType, CollectionCoinType>>(pool_account_address);
        let current_spot_price = pool.spot_price;
        let collection = pool.collection;
        let token_creator = pool.token_creator;
        assert_valid_cointype<CollectionCoinType>(collection, token_creator);
        assert!(vector::length(token_names) > 0, EMPTY_NFTS_INPUT);

        // compute coin amount
        let added_token_count = vector::length(token_names);
        let coin_amount = added_token_count * pool.spot_price;
        assert!(coin_amount <= max_coin_amount, EXCEED_MAX_COIN);
        let c = coin::withdraw<CoinType>(account, coin_amount);
        coin::merge(&mut pool.reserve, c);

        let current_token_count_in_pool = table_with_length::length<token::TokenId, token::Token>(&pool.tokens);
        let current_liquid_supply = option::extract<u128>(&mut coin::supply<LiquidityCoin<CoinType, CollectionCoinType>>());

        let liquidity = (current_liquid_supply as u64) * added_token_count / current_token_count_in_pool;

        let sender = signer::address_of(account);
        let liquidity_coin = coin::mint<LiquidityCoin<CoinType, CollectionCoinType>>(liquidity, &pool.mint_capability);
        if (!coin::is_account_registered<LiquidityCoin<CoinType, CollectionCoinType>>(sender)) {
            coin::register<LiquidityCoin<CoinType, CollectionCoinType>>(account);
        };
        coin::deposit(sender, liquidity_coin);

        let token_ids = internal_get_tokens_to_pool<CoinType, CollectionCoinType>(account, pool, collection, token_names, token_creator, property_version);
        
       update_oracle<CoinType, CollectionCoinType>(pool, current_spot_price);

        let events_store = borrow_global_mut<EventsStore<CoinType, CollectionCoinType>>(pool_account_address);
        event::emit_event(
            &mut events_store.liquidity_added_handle,
            LiquidityAddedEvent<CoinType, CollectionCoinType> {
                collection: collection,
                token_creator: token_creator,
                token_ids: token_ids,
                coin_amount: coin_amount,
                lp_amount: liquidity,
                timestamp: timestamp::now_seconds()
            }
        )
    }

    public entry fun add_liquidity_script<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    max_coin_amount: u64,
                                    token_names: vector<String>,
                                    property_version: u64) acquires Pool, PoolAccountCap, EventsStore {
        add_liquidity<CoinType, CollectionCoinType>(account, max_coin_amount, &token_names, property_version)
    }

    public fun remove_liquidity<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    min_coin_amount: u64, 
                                    min_nfts: u64,
                                    lp_amount: u64) acquires Pool, PoolAccountCap, EventsStore {
        assert_no_emergency();
        let (pool_account_address, _) = get_pool_account_signer();
        assert!(exists<Pool<CoinType, CollectionCoinType>>(pool_account_address), PAIR_NOT_EXISTS); 
        assert!(lp_amount > 0, LP_MUST_GREATER_THAN_ZERO);

        let pool = borrow_global_mut<Pool<CoinType, CollectionCoinType>>(pool_account_address);
        let current_spot_price = pool.spot_price;
        let collection = pool.collection;
        let token_creator = pool.token_creator;
        assert_valid_cointype<CollectionCoinType>(collection, token_creator);

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

        assert!(withdrawnable_coin_amount >= min_coin_amount, INSUFFICIENT_OUTPUT_AMOUNT);
        assert!(num_nfts_to_withdraw >= min_nfts, INSUFFICIENT_NFTS);

        coin::burn(lp_coin, &pool.burn_capability);
        //get token id list
        let i = 0; 
        let token_ids = vector::empty<token::TokenId>();
        while (i < num_nfts_to_withdraw) {
            let token_id = vector::pop_back(&mut pool.token_ids_list);
            vector::push_back<token::TokenId>(&mut token_ids, token_id);
            let token = table_with_length::remove<token::TokenId, token::Token>(&mut pool.tokens, token_id);
            token::deposit_token(account, token);
            i = i + 1;
        };

        let withdrawnable_coin = coin::extract<CoinType>(&mut pool.reserve, withdrawnable_coin_amount);
        let sender = signer::address_of(account);
        if (!coin::is_account_registered<CoinType>(sender)) {
            coin::register<CoinType>(account);
        };
        coin::deposit(sender, withdrawnable_coin);

        update_oracle<CoinType, CollectionCoinType>(pool, current_spot_price);

        let events_store = borrow_global_mut<EventsStore<CoinType, CollectionCoinType>>(pool_account_address);
        event::emit_event(
            &mut events_store.liquidity_removed_handle,
            LiquidityRemovedEvent<CoinType, CollectionCoinType> {
                collection: collection,
                token_creator: pool.token_creator,
                token_ids: token_ids,
                coin_amount: withdrawnable_coin_amount,
                lp_amount: lp_amount,
                timestamp: timestamp::now_seconds()
            }
        )
    }

    public entry fun remove_liquidity_script<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    min_coin_amount: u64, 
                                    min_nfts: u64,
                                    lp_amount: u64) acquires Pool, PoolAccountCap, EventsStore {
        remove_liquidity<CoinType, CollectionCoinType>(account, min_coin_amount, min_nfts, lp_amount)
    }

    public entry fun swap_coin_to_any_tokens_script<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    num_nfts: u64,
                                    max_coin_amount: u64) acquires Pool, PoolAccountCap, EventsStore {
        swap_coin_to_any_tokens<CoinType, CollectionCoinType>(account, num_nfts, max_coin_amount)
    }

    public fun swap_coin_to_any_tokens<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    num_nfts: u64,
                                    max_coin_amount: u64) acquires Pool, PoolAccountCap, EventsStore {
        assert_no_emergency();
        let (pool_account_address, _) = get_pool_account_signer();
        assert!(exists<Pool<CoinType, CollectionCoinType>>(pool_account_address), PAIR_NOT_EXISTS); 
        assert!(num_nfts > 0, NUM_NFTS_MUST_GREATER_THAN_ZERO);

        let pool = borrow_global_mut<Pool<CoinType, CollectionCoinType>>(pool_account_address);
        let current_spot_price = pool.spot_price;
        let collection = pool.collection;
        let token_creator = pool.token_creator;
        assert_valid_cointype<CollectionCoinType>(collection, token_creator);

        assert!(pool.pool_type == POOL_TYPE_TOKEN || pool.pool_type == POOL_TYPE_TRADING, WRONG_POOL_TYPE);

        let current_token_count_in_pool = table_with_length::length<token::TokenId, token::Token>(&pool.tokens);
        assert!(num_nfts <= current_token_count_in_pool, NOT_ENOUGH_NFT_IN_POOL);

        let (protocol_fee, input_value) = update_buy_info<CoinType, CollectionCoinType>(pool, num_nfts, max_coin_amount, PROTOCOL_FEE_MULTIPLIER);

        // send tokens to buyer
        let i = 0; 
        let token_ids = vector::empty<token::TokenId>();
        while (i < num_nfts) {
            let token_id = vector::pop_back(&mut pool.token_ids_list);
            vector::push_back<token::TokenId>(&mut token_ids, token_id);
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
            coin::merge<CoinType>(&mut pool.reserve, input_coin);
        } else {
            // send coin to asset_recipient
            coin::deposit(pool.asset_recipient, input_coin);
        };

        update_oracle<CoinType, CollectionCoinType>(pool, current_spot_price);

        let events_store = borrow_global_mut<EventsStore<CoinType, CollectionCoinType>>(pool_account_address);
        event::emit_event(
            &mut events_store.swap_coin_to_tokens_handle,
            SwapCoinToTokensEvent<CoinType, CollectionCoinType> {
                collection: collection,
                token_creator: token_creator,
                token_ids: token_ids,
                coin_amount: input_value,
                new_spot_price: pool.spot_price,
                timestamp: timestamp::now_seconds()
            }
        )
    }

    public entry fun swap_coin_to_specific_tokens<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    token_names: vector<String>,
                                    property_version: u64,
                                    max_coin_amount: u64) acquires Pool, PoolAccountCap, EventsStore
                                     {
        swap_coin_to_specific<CoinType, CollectionCoinType>(account, &token_names, property_version, max_coin_amount)
    }

    public fun swap_coin_to_specific<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    token_names: &vector<String>,
                                    property_version: u64,
                                    max_coin_amount: u64) acquires Pool, PoolAccountCap, EventsStore {
        assert_no_emergency();
        let (pool_account_address, _) = get_pool_account_signer();
        assert!(exists<Pool<CoinType, CollectionCoinType>>(pool_account_address), PAIR_NOT_EXISTS); 
        let num_nfts = vector::length(token_names);
        assert!(num_nfts > 0, NUM_NFTS_MUST_GREATER_THAN_ZERO);

        let pool = borrow_global_mut<Pool<CoinType, CollectionCoinType>>(pool_account_address);
        let current_spot_price = pool.spot_price;
        let collection = pool.collection;
        let token_creator = pool.token_creator;
        assert_valid_cointype<CollectionCoinType>(collection, token_creator);

        assert!(pool.pool_type == POOL_TYPE_TOKEN || pool.pool_type == POOL_TYPE_TRADING, WRONG_POOL_TYPE);

        let current_token_count_in_pool = table_with_length::length<token::TokenId, token::Token>(&pool.tokens);
        assert!(num_nfts <= current_token_count_in_pool, NOT_ENOUGH_NFT_IN_POOL);

        let (protocol_fee, input_value) = update_buy_info<CoinType, CollectionCoinType>(pool, num_nfts, max_coin_amount, PROTOCOL_FEE_MULTIPLIER);

        // send tokens to buyer
        let i = 0; 
        let token_ids = vector::empty<token::TokenId>();
        while (i < num_nfts) {
            let token_id = token::create_token_id_raw(token_creator, collection, *vector::borrow<String>(token_names, i), property_version);
            vector::push_back<token::TokenId>(&mut token_ids, token_id);
            let token = table_with_length::remove<token::TokenId, token::Token>(&mut pool.tokens, token_id);
            // removing token_id from token_ids_list
            remove_token_id_from_pool_list(&mut pool.token_ids_list, token_id);
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
            coin::merge<CoinType>(&mut pool.reserve, input_coin);
        } else {
            // send coin to asset_recipient
            coin::deposit(pool.asset_recipient, input_coin);
        };
        update_oracle<CoinType, CollectionCoinType>(pool, current_spot_price);
        let events_store = borrow_global_mut<EventsStore<CoinType, CollectionCoinType>>(pool_account_address);
        event::emit_event(
            &mut events_store.swap_coin_to_tokens_handle,
            SwapCoinToTokensEvent<CoinType, CollectionCoinType> {
                collection: collection,
                token_creator: token_creator,
                token_ids: token_ids,
                coin_amount: input_value,
                new_spot_price: pool.spot_price,
                timestamp: timestamp::now_seconds()
            }
        )
    }

    public entry fun swap_tokens_to_coin_script<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    token_names: vector<String>,
                                    min_coin_output: u64,
                                    property_version: u64) acquires Pool, PoolAccountCap, EventsStore {
        swap_tokens_to_coin<CoinType, CollectionCoinType>(account, &token_names, min_coin_output, property_version);
    }

    public fun swap_tokens_to_coin<CoinType, CollectionCoinType> (
                                    account: &signer,
                                    token_names: &vector<String>,
                                    min_coin_output: u64,
                                    property_version: u64) acquires Pool, PoolAccountCap, EventsStore {
        assert_no_emergency();
        let (pool_account_address, _) = get_pool_account_signer();
        assert!(exists<Pool<CoinType, CollectionCoinType>>(pool_account_address), PAIR_NOT_EXISTS); 
        let num_nfts = vector::length(token_names);
        assert!(num_nfts > 0, NUM_NFTS_MUST_GREATER_THAN_ZERO);

        let pool = borrow_global_mut<Pool<CoinType, CollectionCoinType>>(pool_account_address);
        let current_spot_price = pool.spot_price;
        let collection = pool.collection;
        let token_creator = pool.token_creator;
        assert_valid_cointype<CollectionCoinType>(collection, token_creator);

        assert!(pool.pool_type == POOL_TYPE_COIN || pool.pool_type == POOL_TYPE_TRADING, WRONG_POOL_TYPE);

        let (protocol_fee, output_amount) = update_sell_info<CoinType, CollectionCoinType>(
            pool, num_nfts, min_coin_output, PROTOCOL_FEE_MULTIPLIER);
        let remain_pool_coin_amount = coin::value(&pool.reserve);
        if (remain_pool_coin_amount < output_amount) {
            output_amount = remain_pool_coin_amount;
        };

        if (remain_pool_coin_amount < protocol_fee) {            
            protocol_fee = remain_pool_coin_amount;
        };

        // transfer output_amount to sender
        let sender = signer::address_of(account);
        let output_amount_coin = coin::extract<CoinType>(&mut pool.reserve, output_amount);
        if (!coin::is_account_registered<CoinType>(sender)) {
            coin::register<CoinType>(account);
        };
        coin::deposit<CoinType>(sender, output_amount_coin);
        if (protocol_fee > 0) {
            let protocol_fee_coin = coin::extract<CoinType>(&mut pool.reserve, protocol_fee);
            coin::merge(&mut pool.protocol_credit_coin, protocol_fee_coin);
        };
        let token_ids = vector::empty<token::TokenId>();
        let new_spot_price = pool.spot_price;
        if (pool.pool_type == POOL_TYPE_TRADING) {
            // get nfts
            token_ids = internal_get_tokens_to_pool<CoinType, CollectionCoinType>(
                                            account, 
                                            pool,
                                            collection, 
                                            token_names, 
                                            token_creator, 
                                            property_version);
        } else {
            let i = 0; 
            while (i < num_nfts) {
                let token_id = token::create_token_id_raw(token_creator, collection, *vector::borrow<String>(token_names, i), property_version);
                vector::push_back<token::TokenId>(&mut token_ids, token_id);
                let token = table_with_length::remove<token::TokenId, token::Token>(&mut pool.tokens, token_id);
                remove_token_id_from_pool_list(&mut pool.token_ids_list, token_id);
                //deposit token for asset recipients to claim
                table_with_length::add<token::TokenId, token::Token>(&mut pool.tokens_for_asset_recipient, token_id, token);
                vector::push_back<token::TokenId>(&mut pool.token_ids_list_asset_recipient, token_id);
                i = i + 1;
            };
        };
        update_oracle<CoinType, CollectionCoinType>(pool, current_spot_price);
        let events_store = borrow_global_mut<EventsStore<CoinType, CollectionCoinType>>(pool_account_address);
        event::emit_event(
            &mut events_store.swap_tokens_to_coin_handle,
            SwapTokensToCoinEvent<CoinType, CollectionCoinType> {
                collection: collection,
                token_creator: token_creator,
                token_ids: token_ids,
                coin_amount: output_amount,
                new_spot_price: new_spot_price,
                timestamp: timestamp::now_seconds()
            }
        )
    }

    public entry fun claim_tokens_script<CoinType, CollectionCoinType>(account: &signer) acquires Pool, PoolAccountCap, EventsStore {
        let i = 0; 
        assert_no_emergency();
        let (pool_account_address, _) = get_pool_account_signer();
        assert!(exists<Pool<CoinType, CollectionCoinType>>(pool_account_address), PAIR_NOT_EXISTS); 

        let pool = borrow_global_mut<Pool<CoinType, CollectionCoinType>>(pool_account_address);
        let collection = pool.collection;
        let token_creator = pool.token_creator;
        assert_valid_cointype<CollectionCoinType>(collection, token_creator);
        let num_nfts = vector::length(&pool.token_ids_list_asset_recipient);
        let token_ids = vector::empty<token::TokenId>();
        while (i < num_nfts) {
            let token_id = vector::pop_back(&mut pool.token_ids_list_asset_recipient);
            vector::push_back<token::TokenId>(&mut token_ids, token_id);
            let token = table_with_length::remove<token::TokenId, token::Token>(&mut pool.tokens, token_id);
            token::deposit_token(account, token);
            i = i + 1;
        };

        let events_store = borrow_global_mut<EventsStore<CoinType, CollectionCoinType>>(pool_account_address);
        event::emit_event(
            &mut events_store.claim_tokens_handle,
            ClaimTokensEvent<CoinType, CollectionCoinType> {
                collection: collection,
                token_creator: token_creator,
                token_ids: token_ids,
                asset_recipient: pool.asset_recipient,
                timestamp: timestamp::now_seconds()
            }
        )
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

    fun remove_token_id_from_pool_list(token_ids_list: &mut vector<token::TokenId>, token_id: token::TokenId) {
        let j = 0;
        let token_ids_count_in_list = vector::length(token_ids_list);
        while (j < token_ids_count_in_list) {
            let item = vector::borrow(token_ids_list, j);
            if (*item == token_id) {
                if (j == token_ids_count_in_list - 1) {
                    vector::pop_back(token_ids_list);
                } else {
                    let last = vector::pop_back(token_ids_list);
                    let element_at_deleted_position = vector::borrow_mut(token_ids_list, j);
                    *element_at_deleted_position = last;
                };
                break
            };
            j = j + 1;
        };
    }

    /// Adds two u128 and makes overflow possible.
    public fun overflow_add(a: u128, b: u128): u128 {
        let r = MAX_U128 - b;
        if (r < a) {
            return a - r - 1
        };
        r = MAX_U128 - a;
        if (r < b) {
            return b - r - 1
        };
        a + b
    }

    /// Update current cumulative prices.
    /// Important: If you want to use the following function take into account prices can be overflowed.
    /// So it's important to use same logic in your math/algo (as Move doesn't allow overflow). See overflow_add.
    fun update_oracle<CoinType, CollectionCoinType>(
        pool: &mut Pool<CoinType, CollectionCoinType>,
        spot_price: u64
    ) acquires 
    PoolAccountCap, EventsStore {
        let last_block_timestamp = pool.last_block_timestamp;
        let block_timestamp = timestamp::now_seconds();
        let time_elapsed = ((block_timestamp - last_block_timestamp) as u128);
        let (pool_account_address, _) = get_pool_account_signer();

        if (time_elapsed > 0) {
            let last_price_cumulative = (spot_price as u128) * (time_elapsed as u128);

            pool.last_price_cumulative = 
            overflow_add(pool.last_price_cumulative, last_price_cumulative);

            let events_store = borrow_global_mut<EventsStore<CoinType, CollectionCoinType>>(pool_account_address);
            event::emit_event(
                &mut events_store.oracle_updated_handle,
                OracleUpdatedEvent<CoinType, CollectionCoinType> {
                    last_price_cumulative: pool.last_price_cumulative,
                    timestamp: timestamp::now_seconds()

                }
            );
        };

        pool.last_block_timestamp = block_timestamp;
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