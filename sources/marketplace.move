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

    const ESELLER_CAN_NOT_BE_BUYER: u64 = 1;
    const FEE_DENOMINATOR: u64 = 10000;
    const FEE_DIVISOR: u64 = 10000;
    const PROTOCOL_FEE_MULTIPLIER: u64 = 100;   //1%

    //error code
    const PAIR_ALREADY_EXISTS: u64 = 1000;
    const INVALID_INPUT_TOKENS: u64 = 1001;
    const EMPTY_NFTS_INPUT: u64 = 1002;
    const PAIR_NOT_EXISTS: u64 = 1003;

    struct Pool<phantom CoinType> has key {
        coin_amount: Coin<CoinType>,
        collection: String,
        tokens: TableWithLength<token::TokenId, token::Token>,
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
        assert!(!exists<Pool<CoinType>>(@collectibleswap), PAIR_ALREADY_EXISTS); 
        assert!(vector::length(token_names) == vector::length(token_creators), INVALID_INPUT_TOKENS);
        assert!(vector::length(token_names) > 0, EMPTY_NFTS_INPUT);
        // initialize new coin type to represent this pair's liquidity
        // coin::initialize checks that signer::address_of(root) == @aubrium so we don't have to check it here
        let (burn_capability, freeze_capability, mint_capability) = coin::initialize<LiquidityCoin<CoinType>>(
            root,
            string::utf8(b"CollectibleSwap NFT AMM LP"),
            string::utf8(b"CSP-NFT-LP"
            
            ),
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
            collection,
            tokens: table_with_length::new(),
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

    struct MarketId has store, drop, copy {
        market_name: String,
        market_address: address,
    }

    struct Market has key {
        market_id: MarketId,
        fee_numerator: u64,
        fee_payee: address,
        signer_cap: account::SignerCapability
    }

    struct MarketEvents has key {
        create_market_event: EventHandle<CreateMarketEvent>,
        list_token_events: EventHandle<ListTokenEvent>,
        buy_token_events: EventHandle<BuyTokenEvent>
    }

    struct OfferStore has key {
        offers: Table<token::TokenId, Offer>
    }

    struct Offer has drop, store {
        market_id : MarketId,
        seller: address,
        price: u64,
    }

    struct CreateMarketEvent has drop, store {
        market_id: MarketId,
        fee_numerator: u64,
        fee_payee: address,
    }

    struct ListTokenEvent has drop, store {
        market_id: MarketId,
        token_id: token::TokenId,
        seller: address,
        price: u64,
        timestamp: u64,
        offer_id: u64
    }

    struct BuyTokenEvent has drop, store {
        market_id: MarketId,
        token_id: token::TokenId,
        seller: address,
        buyer: address,
        price: u64,
        timestamp: u64,
        offer_id: u64
    }

    fun get_resource_account_cap(market_address : address) : signer acquires Market{
        let market = borrow_global<Market>(market_address);
        account::create_signer_with_capability(&market.signer_cap)
    }

    public entry fun create_market<CoinType>(sender: &signer, market_name: String, fee_numerator: u64, fee_payee: address, initial_fund: u64) acquires MarketEvents, Market {        
        let sender_addr = signer::address_of(sender);
        let market_id = MarketId { market_name, market_address: sender_addr };
        if(!exists<MarketEvents>(sender_addr)){
            move_to(sender, MarketEvents{
                create_market_event: account::new_event_handle<CreateMarketEvent>(sender),
                list_token_events: account::new_event_handle<ListTokenEvent>(sender),
                buy_token_events: account::new_event_handle<BuyTokenEvent>(sender)
            });
        };
        if(!exists<OfferStore>(sender_addr)){
            move_to(sender, OfferStore{
                offers: table::new()
            });
        };
        if(!exists<Market>(sender_addr)){
            let (resource_signer, signer_cap) = account::create_resource_account(sender, x"01");
            token::initialize_token_store(&resource_signer);
            move_to(sender, Market{
                market_id, fee_numerator, fee_payee, signer_cap
            });
            let market_events = borrow_global_mut<MarketEvents>(sender_addr);
            event::emit_event(&mut market_events.create_market_event, CreateMarketEvent{ market_id, fee_numerator, fee_payee });
        };
        let resource_signer = get_resource_account_cap(sender_addr);
        if(!coin::is_account_registered<CoinType>(signer::address_of(&resource_signer))){
            coin::register<CoinType>(&resource_signer);
        };
        if(initial_fund > 0){
            coin::transfer<CoinType>(sender, signer::address_of(&resource_signer), initial_fund);
        }
    }

    public entry fun list_token<CoinType>(seller: &signer, market_address:address, market_name: String, creator: address, collection: String, name: String, property_version: u64, price: u64) acquires MarketEvents, Market, OfferStore {
        let market_id = MarketId { market_name, market_address };
        let resource_signer = get_resource_account_cap(market_address);
        let seller_addr = signer::address_of(seller);
        let token_id = token::create_token_id_raw(creator, collection, name, property_version);
        let token = token::withdraw_token(seller, token_id, 1);

        token::deposit_token(&resource_signer, token);
        list_token_for_swap<CoinType>(&resource_signer, creator, collection, name, property_version, 1, price, 0);

        let offer_store = borrow_global_mut<OfferStore>(market_address);
        table::add(&mut offer_store.offers, token_id, Offer {
            market_id, seller: seller_addr, price
        });

        let guid = account::create_guid(&resource_signer);
        let market_events = borrow_global_mut<MarketEvents>(market_address);
        event::emit_event(&mut market_events.list_token_events, ListTokenEvent{
            market_id, 
            token_id, 
            seller: seller_addr, 
            price, 
            timestamp: timestamp::now_microseconds(),
            offer_id: guid::creation_num(&guid)
        });
    } 

    public entry fun buy_token<CoinType>(buyer: &signer, market_address: address, market_name: String,creator: address, collection: String, name: String, property_version: u64, price: u64, offer_id: u64) acquires MarketEvents, Market, OfferStore{
        let market_id = MarketId { market_name, market_address };
        let token_id = token::create_token_id_raw(creator, collection, name, property_version);
        let offer_store = borrow_global_mut<OfferStore>(market_address);
        let seller = table::borrow(&offer_store.offers, token_id).seller;
        let buyer_addr = signer::address_of(buyer);
        assert!(seller != buyer_addr, ESELLER_CAN_NOT_BE_BUYER);

        let resource_signer = get_resource_account_cap(market_address);
        exchange_coin_for_token<CoinType>(buyer, price, signer::address_of(&resource_signer), creator, collection, name, property_version, 1);
        
        let market = borrow_global<Market>(market_address);
        let market_fee = price * market.fee_numerator / FEE_DENOMINATOR;
        let amount = price - market_fee;
        coin::transfer<CoinType>(&resource_signer, seller, amount);
        table::remove(&mut offer_store.offers, token_id);
        let market_events = borrow_global_mut<MarketEvents>(market_address);
        event::emit_event(&mut market_events.buy_token_events, BuyTokenEvent{
            market_id,
            token_id, 
            seller, 
            buyer: buyer_addr, 
            price,
            timestamp: timestamp::now_microseconds(),
            offer_id
        });
    }
}