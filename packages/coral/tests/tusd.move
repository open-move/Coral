#[test_only]
module coral::tusd;

use sui::coin::{Self, TreasuryCap, CoinMetadata};

public struct TUSD has drop{}

public fun create_tusd(ctx: &mut TxContext): (TreasuryCap<TUSD>, CoinMetadata<TUSD>) {
    coin::create_currency(TUSD {}, 9, b"TUSD", b"Test USD", b"", option::none(), ctx)
}