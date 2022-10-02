#[test_only]
module test_coin_admin::test_helpers {
    use std::string::utf8;
    use std::signer;
    use std::vector;
    use std::string::{Self, String};

    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability};
    use aptos_framework::account;
    use collectibleswap::pool;

    use aptos_token::token;
    use std::option;
    use collectibleswap::type_registry;

    use liquidity_account::liquidity_coin::LiquidityCoin;
    use collectibleswap::to_string;
    use aptos_framework::genesis;


    const INITIAL_SPOT_PRICE: u64 = 900;
    const DELTA: u64 = 100;
    const FEE: u64 = 125;   //1.25%
    const PROTOCOL_FEE_MULTIPLIER: u64 = 25;   //0.25%
    const CURVE_TYPE: u8 = 0;
    const POOL_TYPE: u8 = 2;

    struct BTC {}

    struct USDT {}

    struct USDC {}

    struct CollectionType1 {}
    struct CollectionType2 {}
    struct CollectionType3 {}

    struct Capabilities<phantom CoinType> has key {
        mint_cap: MintCapability<CoinType>,
        burn_cap: BurnCapability<CoinType>,
    }

    // Register one coin with custom details.
    public fun register_coin<CoinType>(coin_admin: &signer, name: vector<u8>, symbol: vector<u8>, decimals: u8) {
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<CoinType>(
            coin_admin,
            utf8(name),
            utf8(symbol),
            decimals,
            true,
        );
        coin::destroy_freeze_cap(freeze_cap);

        move_to(coin_admin, Capabilities<CoinType> {
            mint_cap,
            burn_cap,
        });
    }

    public fun create_collection_coin<CoinType>(coin_admin: &signer) {
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<CoinType>(
            coin_admin,
            utf8(b"name"),
            utf8(b"symbol"),
            1,
            true,
        );
        coin::destroy_freeze_cap(freeze_cap);

        move_to(coin_admin, Capabilities<CoinType> {
            mint_cap,
            burn_cap,
        });
    }

    public fun create_coin_admin(): signer {
        account::create_account_for_test(@test_coin_admin)
    }

    public fun create_aptos_framework(): signer {
        account::create_account_for_test(@aptos_framework)
    }

    public fun create_admin_with_coins(): signer {
        let coin_admin = create_coin_admin();
        register_coins(&coin_admin);
        coin_admin
    }

    // Register all known coins in one func.
    public fun register_coins(coin_admin: &signer) {
        let (usdt_burn_cap, usdt_freeze_cap, usdt_mint_cap) =
            coin::initialize<USDT>(
                coin_admin,
                utf8(b"USDT"),
                utf8(b"USDT"),
                6,
                true
            );

        let (btc_burn_cap, btc_freeze_cap, btc_mint_cap) =
            coin::initialize<BTC>(
                coin_admin,
                utf8(b"BTC"),
                utf8(b"BTC"),
                8,
                true
            );

        let (usdc_burn_cap, usdc_freeze_cap, usdc_mint_cap) =
            coin::initialize<USDC>(
                coin_admin,
                utf8(b"USDC"),
                utf8(b"USDC"),
                4,
                true,
            );

        move_to(coin_admin, Capabilities<USDT> {
            mint_cap: usdt_mint_cap,
            burn_cap: usdt_burn_cap,
        });

        move_to(coin_admin, Capabilities<BTC> {
            mint_cap: btc_mint_cap,
            burn_cap: btc_burn_cap,
        });

        move_to(coin_admin, Capabilities<USDC> {
            mint_cap: usdc_mint_cap,
            burn_cap: usdc_burn_cap,
        });

        coin::destroy_freeze_cap(usdt_freeze_cap);
        coin::destroy_freeze_cap(usdc_freeze_cap);
        coin::destroy_freeze_cap(btc_freeze_cap);

        assert!(
            exists<Capabilities<USDT>>(signer::address_of(coin_admin)), 2000)        
    }

    public fun mint<CoinType>(coin_admin: &signer, amount: u64): Coin<CoinType> acquires Capabilities {
        let caps = borrow_global<Capabilities<CoinType>>(signer::address_of(coin_admin));
        coin::mint(amount, &caps.mint_cap)
    }

    public fun mint_to<CoinType>(coin_admin: &signer, amount: u64) acquires Capabilities {
        let c = mint<CoinType>(coin_admin, amount);
        if (!coin::is_account_registered<CoinType>(signer::address_of(coin_admin))) {
            coin::register<CoinType>(coin_admin);
        };

        coin::deposit<CoinType>(signer::address_of(coin_admin), c)
    }

    public fun burn<CoinType>(coin_admin: &signer, coins: Coin<CoinType>) acquires Capabilities {
        if (coin::value(&coins) == 0) {
            coin::destroy_zero(coins);
        } else {
            let caps = borrow_global<Capabilities<CoinType>>(signer::address_of(coin_admin));
            coin::burn(coins, &caps.burn_cap);
        };
    }

    public fun create_lp_owner(): signer {
        let pool_owner = account::create_account_for_test(@test_lp_owner);
        pool_owner
    }

    public fun create_token_creator(): signer {
        let token_creator = account::create_account_for_test(@test_token_creator);
        token_creator
    }

    public fun create_collectibleswap_admin(): signer {
        let admin = account::create_account_for_test(@collectibleswap);
        admin
    }

    public fun create_coin_admin_and_lp_owner(): (signer, signer) {
        let coin_admin = create_coin_admin();
        let lp_owner = create_lp_owner();
        (coin_admin, lp_owner)
    }

    public fun initialize_token_names(): vector<String> {
        get_token_names(1, 5)
    }

    public fun get_token_names(from: u64, to: u64): vector<String> {
        let ret = vector::empty<String>();
        let i = from;
        while (i < to) {
            let token_name = utf8(b"token-");
            string::append(&mut token_name, to_string::to_string((i as u128)));
            vector::push_back(&mut ret, token_name);
            i = i + 1;
        };
        ret
    }

    public fun get_lp_supply<CoinType, CollectionType>(): u128 {
        let supply = coin::supply<LiquidityCoin<USDC, CollectionType1>>();
        let liquidity_coin_supply = option::extract(&mut supply);
        liquidity_coin_supply
    }

    public fun mint_tokens(token_creator: &signer, recipient: &signer, collection: vector<u8>, token_names: vector<String>) {
        let collection_name = utf8(collection);

        let token_mutate_setting = vector::empty<bool>();
        vector::push_back<bool>(&mut token_mutate_setting, false);
        vector::push_back<bool>(&mut token_mutate_setting, false);
        vector::push_back<bool>(&mut token_mutate_setting, false);
        vector::push_back<bool>(&mut token_mutate_setting, false);
        vector::push_back<bool>(&mut token_mutate_setting, false);

        let i = 0;
        let tokens_count = vector::length(&token_names);
        while (i < tokens_count) {
            token::create_token_script(
                token_creator, 
                collection_name, 
                *vector::borrow(&token_names, i), 
                utf8(b"token description"),
                1,
                1,
                utf8(b"token uri"),
                signer::address_of(token_creator),
                2,
                2,
                token_mutate_setting,
                vector::empty(),
                vector::empty(),
                vector::empty()
                );
            let token_id = token::create_token_id_raw(signer::address_of(token_creator), collection_name, *vector::borrow<String>(&token_names, i), 0);
            assert!(token::balance_of(signer::address_of(token_creator), token_id) == 1, 2);
            let token = token::withdraw_token(token_creator, token_id, 1);
            token::deposit_token(recipient, token);
            i = i + 1;
        }
    }

    public fun initialize_collection_registry(admin: &signer) {
        type_registry::initialize_script(admin)
    }

    public fun create_new_pool<CoinType, CollectionType>(coin_admin: &signer, collection: vector<u8>) {
        pool::create_new_pool_script<USDC, CollectionType1>(
                    coin_admin, 
                    utf8(collection), 
                    initialize_token_names(),
                    @test_token_creator,
                    1,
                    0,
                    0,
                    @test_asset_recipient,
                    DELTA,
                    0
        )
    }

    public fun create_new_pool_success<CoinType, CollectionType>(coin_admin: &signer, token_creator: &signer, collection: vector<u8>, curve_type: u8, pool_type: u8) acquires Capabilities {
        type_registry::register<CollectionType>(utf8(collection), signer::address_of(token_creator));

        let mutate_setting = vector::empty<bool>();
        vector::push_back<bool>(&mut mutate_setting, false);
        vector::push_back<bool>(&mut mutate_setting, false);
        vector::push_back<bool>(&mut mutate_setting, false);

        token::create_collection_script(token_creator, 
                                        utf8(collection), 
                                        utf8(b"description"), 
                                        utf8(b"uri"), 
                                        100, 
                                        mutate_setting);

        mint_tokens(token_creator, coin_admin, collection, initialize_token_names());

        //mint coin USDC
        mint_to<CoinType>(coin_admin, 200000);

        pool::create_new_pool_script<CoinType, CollectionType>(
                            coin_admin, 
                            utf8(collection), 
                            initialize_token_names(),
                            @test_token_creator,
                            INITIAL_SPOT_PRICE,
                            curve_type,
                            pool_type,
                            @test_asset_recipient,
                            DELTA,
                            0
                );
        let  (
            reserve_amount, 
            protocol_credit_coin_amount, 
            pool_collection, 
            pool_token_creator, 
            token_count, 
            _, 
            _,
            spot_price,
            curve_type,
            pool_type,
            asset_recipient,
            delta,
            _,
            _,
            _,
            _,
            _,
            _ 
        ) = pool::get_pool_info<CoinType, CollectionType>();

        assert!(reserve_amount == 4 * INITIAL_SPOT_PRICE, 3);
        assert!(protocol_credit_coin_amount == 0, 3);
        assert!(pool_collection == utf8(collection), 3);
        assert!(pool_token_creator == @test_token_creator, 3);
        assert!(token_count == 4, 3);
        assert!(spot_price == INITIAL_SPOT_PRICE, 3);
        assert!(curve_type == curve_type, 3);
        assert!(pool_type == pool_type, 3);


        assert!(pool_token_creator == @test_token_creator, 3);
        assert!(asset_recipient == @test_asset_recipient, 3);
        assert!(delta == DELTA, 3);

        let supply = coin::supply<LiquidityCoin<CoinType, CollectionType>>();
        let liquidity_coin_supply = option::extract(&mut supply);
        assert!(liquidity_coin_supply == 60, 4);
        assert!(pool::check_pool_valid<CoinType, CollectionType>(), 4)
    }

    public fun prepare(): (signer, signer, signer) {
        genesis::setup();
        let collectibleswap_admin = create_collectibleswap_admin();
        let coin_admin = create_admin_with_coins();
        let token_creator = 
        
        create_token_creator();

        pool::initialize_script(&collectibleswap_admin);
        initialize_collection_registry(&collectibleswap_admin);
        (collectibleswap_admin, coin_admin, token_creator)
    }
}
