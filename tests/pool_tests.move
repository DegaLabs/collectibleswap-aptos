#[test_only]
module collectibleswap::pool_tests {
    use std::signer;
    use std::string::utf8;
    use std::string::{Self, String};
    use std::vector;
    use collectibleswap::pool;
    use aptos_token::token;
    use aptos_framework::coin;
    use std::option;
    use collectibleswap::type_registry;
    use test_coin_admin::test_helpers;
    use test_coin_admin::test_helpers:: {CollectionType1, CollectionType2, CollectionType3, USDC};
    use liquidity_account::liquidity_coin::LiquidityCoin;
    use collectibleswap::to_string;
    use aptos_framework::genesis;
    const INITIAL_SPOT_PRICE: u64 = 900;
    const DELTA: u64 = 100;
    const FEE: u64 = 125;   //1.25%
    const PROTOCOL_FEE_MULTIPLIER: u64 = 25;   //0.25%
    const CURVE_TYPE: u8 = 0;
    const POOL_TYPE: u8 = 2;
    fun initialize_token_names(): vector<String> {
        get_token_names(1, 5)
    }

    fun get_token_names(from: u64, to: u64): vector<String> {
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

    fun get_lp_supply<CoinType, CollectionType>(): u128 {
        let supply = coin::supply<LiquidityCoin<USDC, CollectionType1>>();
        let liquidity_coin_supply = option::extract(&mut supply);
        liquidity_coin_supply
    }

    fun mint_tokens(token_creator: &signer, recipient: &signer, collection: vector<u8>, token_names: vector<String>) {
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

    fun initialize_collection_registry(admin: &signer) {
        type_registry::initialize_script(admin)
    }

    fun create_new_pool<CoinType, CollectionType>(coin_admin: &signer, collection: vector<u8>) {
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

    fun create_new_pool_success<CoinType, CollectionType>(coin_admin: &signer, token_creator: &signer, collection: vector<u8>, curve_type: u8, pool_type: u8) {
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
        test_helpers::mint_to<CoinType>(coin_admin, 200000);

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

    fun prepare(): (signer, signer, signer) {
        genesis::setup();
        let collectibleswap_admin = test_helpers::create_collectibleswap_admin();
        let coin_admin = test_helpers::create_admin_with_coins();
        let token_creator = test_helpers::create_token_creator();

        pool::initialize_script(&collectibleswap_admin);
        initialize_collection_registry(&collectibleswap_admin);
        (collectibleswap_admin, coin_admin, token_creator)
    }

    #[test]
    fun test_plus() {
        let admin = test_helpers::create_collectibleswap_admin();
        assert!(signer::address_of(&admin) == @collectibleswap, 1);
    }

    #[test]
    #[expected_failure(abort_code = 1018)]
    fun test_cannot_reinitialize_contract() {
        let collectibleswap_admin = test_helpers::create_collectibleswap_admin();
        pool::initialize_script(&collectibleswap_admin);
        pool::initialize_script(&collectibleswap_admin);
    }

    #[test]
    fun test_pool_cap_exist() {
        let collectibleswap_admin = test_helpers::create_collectibleswap_admin();
        pool::initialize_script(&collectibleswap_admin);
        assert!(pool::is_pool_cap_initialized(), 1);
        assert!(pool::get_pool_resource_account_address() == @liquidity_account, 2);
    }

    #[test]
    #[expected_failure(abort_code = 3005)]
    fun test_failed_create_new_pool_not_register_collection_type() {
        let collectibleswap_admin = test_helpers::create_collectibleswap_admin();
        pool::initialize_script(&collectibleswap_admin);
        let coin_admin = test_helpers::create_admin_with_coins();
        assert!(signer::address_of(&coin_admin) == @test_coin_admin, 1);

        initialize_collection_registry(&collectibleswap_admin);
        create_new_pool<USDC, CollectionType1>(&coin_admin, b"collection1")
    }


    #[test]
    fun test_create_new_pool_success() {
        let (_, coin_admin, token_creator) = prepare();

        create_new_pool_success<USDC, CollectionType1>(&coin_admin, &token_creator, b"collection1", CURVE_TYPE, POOL_TYPE);
        create_new_pool_success<USDC, CollectionType2>(&coin_admin, &token_creator, b"collection2", CURVE_TYPE, POOL_TYPE);
        create_new_pool_success<USDC, CollectionType3>(&coin_admin, &token_creator, b"collection3", CURVE_TYPE, POOL_TYPE)
    }

    #[test]
    #[expected_failure]
    fun pool_already_exist() {
        let (_, coin_admin, token_creator) = prepare();

        create_new_pool_success<USDC, CollectionType1>(&coin_admin, &token_creator, b"collection1", CURVE_TYPE, POOL_TYPE);
        create_new_pool_success<CollectionType1, USDC>(&coin_admin, &token_creator, b"collection2", CURVE_TYPE, POOL_TYPE);
    }

    #[test]
    fun add_liquidity() {
        let (_, coin_admin, token_creator) = prepare();

        create_new_pool_success<USDC, CollectionType1>(&coin_admin, &token_creator, b"collection1", CURVE_TYPE, POOL_TYPE);
        
        let token_names = get_token_names(5, 9);
        mint_tokens(&token_creator, &coin_admin, b"collection1", token_names);

        pool::add_liquidity_script<USDC, CollectionType1>(&coin_admin, 1000000, token_names, 0);

        let supply = coin::supply<LiquidityCoin<USDC, CollectionType1>>();
        let liquidity_coin_supply = option::extract(&mut supply);
        assert!(liquidity_coin_supply == 120, 4);
        assert!(pool::check_pool_valid<USDC, CollectionType1>(), 4);
    }

    #[test]
    fun remove_liquidity_even() {
        let (_, coin_admin, token_creator) = prepare();

        create_new_pool_success<USDC, CollectionType1>(&coin_admin, &token_creator, b"collection1", CURVE_TYPE, POOL_TYPE);
        
        let token_names = get_token_names(5, 9);
        mint_tokens(&token_creator, &coin_admin, b"collection1", token_names);

        pool::add_liquidity_script<USDC, CollectionType1>(&coin_admin, 1000000, token_names, 0);

        assert!(get_lp_supply<USDC, CollectionType1>() == 120, 4);

        let usdc_balance = coin::balance<USDC>(@test_coin_admin);

        pool::remove_liquidity<USDC, CollectionType1>(&coin_admin, 0, 0, 60);

        assert!(get_lp_supply<USDC, CollectionType1>() == 60, 4);    
        assert!(usdc_balance + 3600 == coin::balance<USDC>(@test_coin_admin), 4);    
        assert!(pool::check_pool_valid<USDC, CollectionType1>(), 4);
    }

    //withdraw 20% lp
    #[test]
    fun remove_liquidity_uneven1() {
        let (_, coin_admin, token_creator) = prepare();

        create_new_pool_success<USDC, CollectionType1>(&coin_admin, &token_creator, b"collection1", CURVE_TYPE, POOL_TYPE);
        
        let token_names = get_token_names(5, 9);
        mint_tokens(&token_creator, &coin_admin, b"collection1", token_names);

        pool::add_liquidity_script<USDC, CollectionType1>(&coin_admin, 1000000, token_names, 0);

        assert!(get_lp_supply<USDC, CollectionType1>() == 120, 4);

        let usdc_balance = coin::balance<USDC>(@test_coin_admin);

        pool::remove_liquidity<USDC, CollectionType1>(&coin_admin, 0, 0, 24);

        assert!(get_lp_supply<USDC, CollectionType1>() == 96, 4);    
        assert!(usdc_balance + 1080 == coin::balance<USDC>(@test_coin_admin), 4);

        let  (
            reserve_amount, 
            protocol_credit_coin_amount, 
            _, 
            _, 
            token_count, 
            _, 
            _,
            spot_price,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            _ 
        ) = pool::get_pool_info<USDC, CollectionType1>();

        assert!(reserve_amount == 7200 - 1080, 4);
        assert!(protocol_credit_coin_amount == 0, 4);
        assert!(token_count == 6, 4);
        assert!(spot_price == INITIAL_SPOT_PRICE, 4);  
        assert!(pool::check_pool_valid<USDC, CollectionType1>(), 4);
    }

    #[test]
    fun remove_liquidity_uneven2() {
        let (_, coin_admin, token_creator) = prepare();

        create_new_pool_success<USDC, CollectionType1>(&coin_admin, &token_creator, b"collection1", CURVE_TYPE, POOL_TYPE);
        
        let token_names = get_token_names(5, 9);
        mint_tokens(&token_creator, &coin_admin, b"collection1", token_names);

        pool::add_liquidity_script<USDC, CollectionType1>(&coin_admin, 1000000, token_names, 0);

        assert!(get_lp_supply<USDC, CollectionType1>() == 120, 4);

        let usdc_balance = coin::balance<USDC>(@test_coin_admin);

        pool::remove_liquidity<USDC, CollectionType1>(&coin_admin, 0, 0, 36);

        assert!(get_lp_supply<USDC, CollectionType1>() == 84, 4);    
        assert!(usdc_balance + 1620 == coin::balance<USDC>(@test_coin_admin), 4);

        let  (
            reserve_amount, 
            protocol_credit_coin_amount, 
            _, 
            _, 
            token_count, 
            _, 
            _,
            spot_price,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            _ 
        ) = pool::get_pool_info<USDC, CollectionType1>();

        assert!(reserve_amount == 7200 - 1620, 4);
        assert!(protocol_credit_coin_amount == 0, 4);
        assert!(token_count == 5, 4);
        assert!(spot_price == INITIAL_SPOT_PRICE, 4);  

        assert!(pool::check_pool_valid<USDC, CollectionType1>(), 4);
    }

    #[test]
    fun remove_liquidity_uneven3() {
        let (_, coin_admin, token_creator) = prepare();

        create_new_pool_success<USDC, CollectionType1>(&coin_admin, &token_creator, b"collection1", CURVE_TYPE, POOL_TYPE);
        
        let token_names = get_token_names(5, 9);
        mint_tokens(&token_creator, &coin_admin, b"collection1", token_names);

        pool::add_liquidity_script<USDC, CollectionType1>(&coin_admin, 1000000, token_names, 0);

        assert!(get_lp_supply<USDC, CollectionType1>() == 120, 4);

        let usdc_balance = coin::balance<USDC>(@test_coin_admin);

        pool::remove_liquidity<USDC, CollectionType1>(&coin_admin, 0, 0, 48);

        assert!(get_lp_supply<USDC, CollectionType1>() == 72, 4);    
        assert!(usdc_balance + 2160 == coin::balance<USDC>(@test_coin_admin), 4);

        let  (
            reserve_amount, 
            protocol_credit_coin_amount, 
            _, 
            _, 
            token_count, 
            _, 
            _,
            spot_price,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            _ 
        ) = pool::get_pool_info<USDC, CollectionType1>();

        assert!(reserve_amount == 7200 - 2160, 4);
        assert!(protocol_credit_coin_amount == 0, 4);
        assert!(token_count == 4, 4);
        assert!(spot_price == INITIAL_SPOT_PRICE, 4);  
        assert!(pool::check_pool_valid<USDC, CollectionType1>(), 4);
    }

    #[test]
    fun test_buy_nfts_1() {
        let (_, coin_admin, token_creator) = prepare();

        create_new_pool_success<USDC, CollectionType1>(&coin_admin, &token_creator, b"collection1", CURVE_TYPE, POOL_TYPE);
        
        let token_names = get_token_names(5, 9);
        mint_tokens(&token_creator, &coin_admin, b"collection1", token_names);

        pool::add_liquidity_script<USDC, CollectionType1>(&coin_admin, 1000000, token_names, 0);

        let balance_before = coin::balance<USDC>(@test_coin_admin);
        // swap
        pool::swap_coin_to_any_tokens_script<USDC, CollectionType1>(&coin_admin, 1, 10000);
        assert!(pool::check_pool_valid<USDC, CollectionType1>(), 4);

        let (
            reserve_amount, 
            protocol_credit_coin_amount, 
            _, 
            _, 
            token_count, 
            _, 
            _,
            spot_price,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            accumulated_volume,
            accumulated_fees,
            unrealized_fee 
        ) = pool::get_pool_info<USDC, CollectionType1>();

        let balance_after = coin::balance<USDC>(@test_coin_admin);
        assert!(balance_before == balance_after + 1015, 4);
        assert!(reserve_amount == 7200 + INITIAL_SPOT_PRICE + DELTA + 12, 4);
        assert!(token_count == 7, 4);
        assert!(spot_price == INITIAL_SPOT_PRICE + DELTA + 1, 4);
        assert!(protocol_credit_coin_amount == 3, 4);
        assert!(unrealized_fee == 5, 4);
        assert!(accumulated_volume == 1000, 4);
        assert!(accumulated_fees == 15, 4);

        balance_before = balance_after;
        // swap
        pool::swap_coin_to_any_tokens_script<USDC, CollectionType1>(&coin_admin, 1, 10000);
        assert!(pool::check_pool_valid<USDC, CollectionType1>(), 4);

        (
            reserve_amount, 
            protocol_credit_coin_amount, 
            _, 
            _, 
            token_count, 
            _, 
            _,
            spot_price,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            accumulated_volume,
            accumulated_fees,
            unrealized_fee 
        ) = pool::get_pool_info<USDC, CollectionType1>();

        balance_after = coin::balance<USDC>(@test_coin_admin);
        assert!(balance_before == balance_after + 1117, 4);
        assert!(reserve_amount == (7200 + INITIAL_SPOT_PRICE + DELTA + 12) + (1101 + 13), 4);
        assert!(token_count == 6, 4);
        assert!(spot_price == (INITIAL_SPOT_PRICE + DELTA + 1) + DELTA + 3, 4);
        assert!(protocol_credit_coin_amount == 6, 4);
        assert!(unrealized_fee == 0, 4);
        assert!(accumulated_volume == 2101, 4);
        assert!(accumulated_fees == 31, 4);
    }

    #[test]
    fun test_sell_nfts_1() {
        let (_, coin_admin, token_creator) = prepare();

        create_new_pool_success<USDC, CollectionType1>(&coin_admin, &token_creator, b"collection1", CURVE_TYPE, POOL_TYPE);
        
        let token_names = get_token_names(5, 9);
        mint_tokens(&token_creator, &coin_admin, b"collection1", token_names);

        pool::add_liquidity_script<USDC, CollectionType1>(&coin_admin, 1000000, token_names, 0);

        mint_tokens(&token_creator, &coin_admin, b"collection1", get_token_names(9, 11));

        let balance_before = coin::balance<USDC>(@test_coin_admin);
        // swap
        pool::swap_tokens_to_coin_script<USDC, CollectionType1>(&coin_admin, get_token_names(9, 10), 0, 0);
        assert!(pool::check_pool_valid<USDC, CollectionType1>(), 4);

        let (
            reserve_amount, 
            protocol_credit_coin_amount, 
            _, 
            _, 
            token_count, 
            _, 
            _,
            spot_price,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            accumulated_volume,
            accumulated_fees,
            unrealized_fee 
        ) = pool::get_pool_info<USDC, CollectionType1>();

        let balance_after = coin::balance<USDC>(@test_coin_admin);
        assert!(balance_after == balance_before + 887, 4);
        assert!(reserve_amount == 7200 - INITIAL_SPOT_PRICE + 11, 4);
        assert!(token_count == 9, 4);
        assert!(spot_price == INITIAL_SPOT_PRICE - DELTA + 1, 4);
        assert!(spot_price == 801, 4);
        assert!(protocol_credit_coin_amount == 2, 4);
        assert!(unrealized_fee == 2, 4);
        assert!(accumulated_volume == 900, 4);
        assert!(accumulated_fees == 13, 4);

        balance_before = balance_after;
        // swap
        pool::swap_tokens_to_coin_script<USDC, CollectionType1>(&coin_admin, get_token_names(10, 11), 0, 0);
        assert!(pool::check_pool_valid<USDC, CollectionType1>(), 4);

        (
            reserve_amount, 
            protocol_credit_coin_amount, 
            _, 
            _, 
            token_count, 
            _, 
            _,
            spot_price,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            accumulated_volume,
            accumulated_fees,
            unrealized_fee 
        ) = pool::get_pool_info<USDC, CollectionType1>();

        balance_after = coin::balance<USDC>(@test_coin_admin);
        assert!(balance_after == balance_before + 789, 4);
        assert!(reserve_amount == 7200 - INITIAL_SPOT_PRICE + 11 - 801 + 10, 4);
        assert!(token_count == 10, 4);
        assert!(spot_price == INITIAL_SPOT_PRICE - DELTA + 1 - DELTA + 1, 4);
        assert!(protocol_credit_coin_amount == 4, 4);
        assert!(unrealized_fee == 2, 4);
        assert!(accumulated_volume == 1701, 4);
        assert!(accumulated_fees == 25, 4);
    }

    #[test]
    fun test_buy_nfts_multi() {
        let (_, coin_admin, token_creator) = prepare();

        create_new_pool_success<USDC, CollectionType1>(&coin_admin, &token_creator, b"collection1", CURVE_TYPE, POOL_TYPE);
        
        let token_names = get_token_names(5, 9);
        mint_tokens(&token_creator, &coin_admin, b"collection1", token_names);

        pool::add_liquidity_script<USDC, CollectionType1>(&coin_admin, 1000000, token_names, 0);

        let balance_before = coin::balance<USDC>(@test_coin_admin);
        // swap
        pool::swap_coin_to_any_tokens_script<USDC, CollectionType1>(&coin_admin, 2, 10000);
        assert!(pool::check_pool_valid<USDC, CollectionType1>(), 4);

        let (
            reserve_amount, 
            protocol_credit_coin_amount, 
            _, 
            _, 
            token_count, 
            _, 
            _,
            spot_price,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            accumulated_volume,
            accumulated_fees,
            unrealized_fee 
        ) = pool::get_pool_info<USDC, CollectionType1>();

        let balance_after = coin::balance<USDC>(@test_coin_admin);
        assert!(balance_before == balance_after + 2132, 4);
        assert!(reserve_amount == (7200 + INITIAL_SPOT_PRICE + DELTA + 12) + (1101 + 13), 4);
        assert!(token_count == 6, 4);
        assert!(spot_price == (INITIAL_SPOT_PRICE + DELTA + 1) + DELTA + 3, 4);
        assert!(protocol_credit_coin_amount == 6, 4);
        assert!(unrealized_fee == 0, 4);
        assert!(accumulated_volume == 2101, 4);
        assert!(accumulated_fees == 31, 4);
    }


    #[test]
    fun test_sell_nfts_multi() {
        let (_, coin_admin, token_creator) = prepare();

        create_new_pool_success<USDC, CollectionType1>(&coin_admin, &token_creator, b"collection1", CURVE_TYPE, POOL_TYPE);
        
        let token_names = get_token_names(5, 9);
        mint_tokens(&token_creator, &coin_admin, b"collection1", token_names);

        pool::add_liquidity_script<USDC, CollectionType1>(&coin_admin, 1000000, token_names, 0);

        mint_tokens(&token_creator, &coin_admin, b"collection1", get_token_names(9, 11));

        let balance_before = coin::balance<USDC>(@test_coin_admin);
        // swap
        pool::swap_tokens_to_coin_script<USDC, CollectionType1>(&coin_admin, get_token_names(9, 11), 0, 0);
        assert!(pool::check_pool_valid<USDC, CollectionType1>(), 4);

        let (
            reserve_amount, 
            protocol_credit_coin_amount, 
            _, 
            _, 
            token_count, 
            _, 
            _,
            spot_price,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            accumulated_volume,
            accumulated_fees,
            unrealized_fee 
        ) = pool::get_pool_info<USDC, CollectionType1>();

        let balance_after = coin::balance<USDC>(@test_coin_admin);
        
        assert!(balance_after == balance_before + 887 + 789, 4);
        assert!(reserve_amount == 7200 - INITIAL_SPOT_PRICE + 11 - 801 + 10, 4);
        assert!(token_count == 10, 4);
        assert!(spot_price == INITIAL_SPOT_PRICE - DELTA + 1 - DELTA + 1, 4);
        assert!(protocol_credit_coin_amount == 4, 4);
        assert!(unrealized_fee == 2, 4);
        assert!(accumulated_volume == 1701, 4);
        assert!(accumulated_fees == 25, 4);
    }

    #[test]
    fun test_buy_nfts_specific_tokens_1() {
        let (_, coin_admin, token_creator) = prepare();

        create_new_pool_success<USDC, CollectionType1>(&coin_admin, &token_creator, b"collection1", CURVE_TYPE, POOL_TYPE);
        
        let token_names = get_token_names(5, 9);
        mint_tokens(&token_creator, &coin_admin, b"collection1", token_names);

        pool::add_liquidity_script<USDC, CollectionType1>(&coin_admin, 1000000, token_names, 0);

        let balance_before = coin::balance<USDC>(@test_coin_admin);
        // swap
        pool::swap_coin_to_specific_tokens_script<USDC, CollectionType1>(&coin_admin, get_token_names(5, 6), 0, 1000000000);
        assert!(pool::check_pool_valid<USDC, CollectionType1>(), 4);

        let (
            reserve_amount, 
            protocol_credit_coin_amount, 
            _, 
            _, 
            token_count, 
            _, 
            _,
            spot_price,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            accumulated_volume,
            accumulated_fees,
            unrealized_fee 
        ) = pool::get_pool_info<USDC, CollectionType1>();

        let balance_after = coin::balance<USDC>(@test_coin_admin);
        assert!(balance_before == balance_after + 1015, 4);
        assert!(reserve_amount == 7200 + INITIAL_SPOT_PRICE + DELTA + 12, 4);
        assert!(token_count == 7, 4);
        assert!(spot_price == INITIAL_SPOT_PRICE + DELTA + 1, 4);
        assert!(protocol_credit_coin_amount == 3, 4);
        assert!(unrealized_fee == 5, 4);
        assert!(accumulated_volume == 1000, 4);
        assert!(accumulated_fees == 15, 4);

        balance_before = balance_after;
        // swap
        pool::swap_coin_to_specific_tokens_script<USDC, CollectionType1>(&coin_admin, get_token_names(6, 7), 0, 1000000000);
        assert!(pool::check_pool_valid<USDC, CollectionType1>(), 4);

        (
            reserve_amount, 
            protocol_credit_coin_amount, 
            _, 
            _, 
            token_count, 
            _, 
            _,
            spot_price,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            accumulated_volume,
            accumulated_fees,
            unrealized_fee 
        ) = pool::get_pool_info<USDC, CollectionType1>();

        balance_after = coin::balance<USDC>(@test_coin_admin);
        assert!(balance_before == balance_after + 1117, 4);
        assert!(reserve_amount == (7200 + INITIAL_SPOT_PRICE + DELTA + 12) + (1101 + 13), 4);
        assert!(token_count == 6, 4);
        assert!(spot_price == (INITIAL_SPOT_PRICE + DELTA + 1) + DELTA + 3, 4);
        assert!(protocol_credit_coin_amount == 6, 4);
        assert!(unrealized_fee == 0, 4);
        assert!(accumulated_volume == 2101, 4);
        assert!(accumulated_fees == 31, 4);
    }

    #[test]
    fun test_buy_nfts_specific_tokens_multi() {
        let (_, coin_admin, token_creator) = prepare();

        create_new_pool_success<USDC, CollectionType1>(&coin_admin, &token_creator, b"collection1", CURVE_TYPE, POOL_TYPE);
        
        let token_names = get_token_names(5, 9);
        mint_tokens(&token_creator, &coin_admin, b"collection1", token_names);

        pool::add_liquidity_script<USDC, CollectionType1>(&coin_admin, 1000000, token_names, 0);

        let balance_before = coin::balance<USDC>(@test_coin_admin);
        // swap
        pool::swap_coin_to_specific_tokens_script<USDC, CollectionType1>(&coin_admin, get_token_names(5, 7), 0, 10000000);
        assert!(pool::check_pool_valid<USDC, CollectionType1>(), 4);

        let (
            reserve_amount, 
            protocol_credit_coin_amount, 
            _, 
            _, 
            token_count, 
            _, 
            _,
            spot_price,
            _,
            _,
            _,
            _,
            _,
            _,
            _,
            accumulated_volume,
            accumulated_fees,
            unrealized_fee 
        ) = pool::get_pool_info<USDC, CollectionType1>();

        let balance_after = coin::balance<USDC>(@test_coin_admin);
        assert!(balance_before == balance_after + 2132, 4);
        assert!(reserve_amount == (7200 + INITIAL_SPOT_PRICE + DELTA + 12) + (1101 + 13), 4);
        assert!(token_count == 6, 4);
        assert!(spot_price == (INITIAL_SPOT_PRICE + DELTA + 1) + DELTA + 3, 4);
        assert!(protocol_credit_coin_amount == 6, 4);
        assert!(unrealized_fee == 0, 4);
        assert!(accumulated_volume == 2101, 4);
        assert!(accumulated_fees == 31, 4);
    }

    #[test]
    #[expected_failure]
    fun test_swap_failed_with_invalid_token() {
        let (_, coin_admin, token_creator) = prepare();

        create_new_pool_success<USDC, CollectionType1>(&coin_admin, &token_creator, b"collection1", CURVE_TYPE, POOL_TYPE);
        
        let token_names = get_token_names(5, 9);
        mint_tokens(&token_creator, &coin_admin, b"collection1", token_names);

        pool::add_liquidity_script<USDC, CollectionType1>(&coin_admin, 1000000, token_names, 0);
        pool::swap_coin_to_specific_tokens_script<USDC, CollectionType1>(&coin_admin, get_token_names(9, 10), 0, 10000000);
    }
}
