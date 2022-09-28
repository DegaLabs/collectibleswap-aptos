#[test_only]
module test_coin_admin::test_helpers {
    use std::string::utf8;
    use std::signer;

    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability};
    use aptos_framework::account;

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

    // public fun setup_coins_and_lp_owner(): (signer, signer) {
    //     genesis::setup();

    //     let liquidswap_admin = account::create_account_for_test(@liquidswap);
    //     let lp_coin_metadata = x"064c50436f696e010000000000000000403239383333374145433830334331323945313337414344443138463135393936323344464146453735324143373738443344354437453231454133443142454389021f8b08000000000002ff2d90c16ec3201044ef7c45e44b4eb13160c0957aeab5952af51845d1b22c8995c45860bbfdfce2b4b79dd59b9dd11e27c01b5ce8c44678d0ee75b77fff7c8bc3b8672ba53cc4715bb535aff99eb123789f2867ca27769fce58b83320c6659c0b56f19f36980e21f4beb5207a05c48d54285b4784ad7306a5e8831460add6ce486dc98014aed78e2b521d5525c3d37af034d1e869c48172fd1157fa9afd7d702776199e49d7799ef24bd314795d5c8df1d1c034c77cb883cbff23c64475012a9668dd4c3668a91c7a41caa2ea8db0da7ace3be965274550c1680ed4f615cb8bf343da3c7fa71ea541135279d0774cb7669387fc6c54b15fb48937414101000001076c705f636f696e5c1f8b08000000000002ff35c8b10980301046e13e53fc0338411027b0b0d42a84535048ee82de5521bb6b615ef5f8b2ec960ea412482e0e91488cd5fb1f501dbe1ebd8d14f3329633b24ac63aa0ef36a136d7dc0b3946fd604b00000000000000";
    //     let lp_coin_code = x"a11ceb0b050000000501000202020a070c170823200a4305000000010003000100010001076c705f636f696e024c500b64756d6d795f6669656c6435e1873b2a1ae8c609598114c527b57d31ff5274f646ea3ff6ecad86c56d2cf8000201020100";

    //     lp_account::initialize_lp_account(
    //         &liquidswap_admin,
    //         lp_coin_metadata,
    //         lp_coin_code
    //     );
    //     // retrieves SignerCapability
    //     liquidity_pool::initialize(&liquidswap_admin);

    //     let coin_admin = test_coins::create_admin_with_coins();
    //     let lp_owner = create_lp_owner();
    //     (coin_admin, lp_owner)
    // }

    // public fun mint_liquidity<X, Y, Curve>(lp_owner: &signer, coin_x: Coin<X>, coin_y: Coin<Y>): u64 {
    //     let lp_owner_addr = signer::address_of(lp_owner);
    //     let lp_coins = liquidity_pool::mint<X, Y, Curve>(coin_x, coin_y);
    //     let lp_coins_val = coin::value(&lp_coins);
    //     if (!coin::is_account_registered<LP<X, Y, Curve>>(lp_owner_addr)) {
    //         coin::register<LP<X, Y, Curve>>(lp_owner);
    //     };
    //     coin::deposit(lp_owner_addr, lp_coins);
    //     lp_coins_val
    // }
}
