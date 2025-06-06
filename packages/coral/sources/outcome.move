module coral::outcome;

use std::type_name::TypeName;

use sui::vec_map::{Self, VecMap};

use interest_math::fixed18::{Self, Fixed18};

use coral::lmsr;

public enum Outcome has copy, store, drop {
    SAFE(TypeName),
    RISKY(TypeName),
}

public struct OutcomeSnapshot {
    market_id: ID,
    data: VecMap<Outcome, u64>,
}

const EDuplicateOutcome: u64 = 1;
const EInvalidOutcomeSnapshot: u64 = 2;
const EMarketIDSnapshotMismatch: u64 = 3;

public fun safe(outcome_type: TypeName): Outcome {
    Outcome::SAFE(outcome_type)
}

public fun risky(outcome_type: TypeName): Outcome {
    Outcome::RISKY(outcome_type)
}

public fun get_type(outcome: &Outcome): &TypeName {
    match (outcome) {
        Outcome::SAFE(t) => t,
        Outcome::RISKY(t) => t
    }
}

public(package) fun create_outcome_snapshot(market_id: ID): OutcomeSnapshot {
    OutcomeSnapshot {
        market_id,
        data: vec_map::empty(),
    }
}

public(package) fun clone_outcome_snapshot(snapshot: &OutcomeSnapshot): OutcomeSnapshot {
    OutcomeSnapshot {
        data: snapshot.data,
        market_id: snapshot.market_id,
    }
}

public(package) fun add_outcome_snapshot_data(snapshot: &mut OutcomeSnapshot, market_id: ID, outcome: Outcome, supply: u64) {
    assert!(snapshot.market_id == market_id, EMarketIDSnapshotMismatch);
    assert!(!snapshot.data.contains(&outcome), EDuplicateOutcome);
    
    snapshot.data.insert(outcome, supply);
}

public(package) fun destroy_snapshot_outcomes(snapshot: OutcomeSnapshot): (vector<Outcome>, vector<u64>) {
    let OutcomeSnapshot { market_id: _, data } = snapshot;

    let (outcomes, balances) = data.into_keys_values();
    assert!(outcomes.length() == 2 && balances.length() == 2, EInvalidOutcomeSnapshot);
    (outcomes, balances)
}

public(package) fun net_cost(snapshot: OutcomeSnapshot, outcome: Outcome, market_id: ID, liquidity_param: Fixed18, amount: Fixed18): Fixed18 {
    assert!(snapshot.market_id == market_id, EMarketIDSnapshotMismatch);
    let (outcomes, balances) = destroy_snapshot_outcomes(snapshot);

    let (has_outcome, outcome_index) = outcomes.index_of(&outcome);
    assert!(has_outcome, EInvalidOutcomeSnapshot);

    let outcome_amounts = balances.map!(|v| { fixed18::from_u64(v) });
    lmsr::net_cost(outcome_amounts, liquidity_param, amount, outcome_index)
}

public(package) fun net_revenue(snapshot: OutcomeSnapshot, outcome: Outcome, market_id: ID, liquidity_param: Fixed18, amount: Fixed18): Fixed18 {
    assert!(snapshot.market_id == market_id, EMarketIDSnapshotMismatch);
    let (outcomes, balances) = destroy_snapshot_outcomes(snapshot);
    
    let (has_outcome, outcome_index) = outcomes.index_of(&outcome);
    assert!(has_outcome, EInvalidOutcomeSnapshot);

    let outcome_amounts = balances.map!(|v| { fixed18::from_u64(v) });
    lmsr::net_revenue(outcome_amounts, liquidity_param, amount, outcome_index)
}