module collectibleswap::collectiontyperegistry {
    use std::vector;
    use std::table;
    use std::signer;
    use std::option;
    use std::string::{Self, String};
    use aptos_std::type_info:: {Self, TypeInfo};

    const ERR_NOT_ENOUGH_PERMISSIONS_TO_INITIALIZE: u64 = 3000;
    const REGISTRY_ALREADY_INITIALIZED: u64 = 3001;
    const REGISTRY_NOT_INITIALIZED: u64 = 3002;
    const COLLECTION_ALREADY_REGISTERED: u64 = 3003;
    const COINTYPE_ALREADY_REGISTERED: u64 = 3004;
    const INVALID_REGISTRATION: u64 = 3005;

    struct CollectionCoinType has store, copy, drop {
        collection: String,
        creator: address
    }

    struct CollectionTypeRegistry has key {
        collection_to_cointype: table::Table<CollectionCoinType, TypeInfo>,
        cointype_to_collection: table::Table<TypeInfo, CollectionCoinType>
    }

    public entry fun initialize_script(collectibleswap_admin: &signer) {
        assert!(signer::address_of(collectibleswap_admin) == @collectibleswap, ERR_NOT_ENOUGH_PERMISSIONS_TO_INITIALIZE);
        assert!(!exists<CollectionTypeRegistry>(@collectibleswap), REGISTRY_ALREADY_INITIALIZED);
        move_to(collectibleswap_admin, CollectionTypeRegistry { collection_to_cointype: table::new(), cointype_to_collection: table::new() });
    }

    public entry fun register<CoinType>(account: &signer, collection: String, creator: address) acquires CollectionTypeRegistry {
        assert!(!exists<CollectionTypeRegistry>(@collectibleswap), REGISTRY_NOT_INITIALIZED);
        let registry = borrow_global_mut<CollectionTypeRegistry>(@collectibleswap);
        let collection_type = CollectionCoinType { collection: collection, creator: creator };
        assert!(!table::contains(&registry.collection_to_cointype, collection_type), COLLECTION_ALREADY_REGISTERED);

        let ti = type_info::type_of<CoinType>();
        assert!(!table::contains(&registry.cointype_to_collection, ti), COINTYPE_ALREADY_REGISTERED);

        table::add(&mut registry.collection_to_cointype, collection_type, ti);
        table::add(&mut registry.cointype_to_collection, ti, collection_type);
    }

    public fun get_registered_cointype(collection: String, creator: address): TypeInfo acquires CollectionTypeRegistry {
        let registry = borrow_global<CollectionTypeRegistry>(@collectibleswap);
        let collection_type = CollectionCoinType { collection: collection, creator: creator };
        let ti = table::borrow(&registry.collection_to_cointype, collection_type);
        return *ti
    }

    public fun get_collection_cointype<CoinType>(): CollectionCoinType acquires CollectionTypeRegistry {
        let registry = borrow_global<CollectionTypeRegistry>(@collectibleswap);
        let ti = type_info::type_of<CoinType>();
        let collection_cointype = table::borrow(&registry.cointype_to_collection, ti);
        return *collection_cointype
    }

    public fun is_valid_registration<CoinType>(collection: String, creator: address): bool acquires CollectionTypeRegistry {
        let registry = borrow_global<CollectionTypeRegistry>(@collectibleswap);
        let collection_type = CollectionCoinType { collection: collection, creator: creator };
        let registered_ti = table::borrow(&registry.collection_to_cointype, collection_type);
        return *registered_ti == type_info::type_of<CoinType>()
    }

    public fun assert_valid_cointype<CoinType>(collection: String, creator: address) acquires CollectionTypeRegistry {
        assert!(is_valid_registration<CoinType>(collection, creator), INVALID_REGISTRATION);
    }
}