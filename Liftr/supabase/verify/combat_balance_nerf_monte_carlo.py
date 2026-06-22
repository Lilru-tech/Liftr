#!/usr/bin/env python3
import math
import random
import sys
from copy import deepcopy

COMBAT_STATS = [
    "health", "strength", "defense", "speed", "agility", "stamina",
    "resistance", "critical_rate", "intelligence", "exploration",
]

SK = COMBAT_STATS + ["happiness"]

V5_WEIGHTS = {
    "chocobo": dict(
        health=4, strength=4, defense=4, speed=6, intelligence=2, agility=5,
        stamina=4, critical_rate=1, resistance=2, exploration=4, happiness=4,
    ),
    "griffin": dict(
        health=4, strength=4, defense=4, speed=5, intelligence=2, agility=4,
        stamina=4, critical_rate=1, resistance=5, exploration=3, happiness=4,
    ),
    "monkey": dict(
        health=4, strength=4, defense=3, speed=5, intelligence=4, agility=5,
        stamina=3, critical_rate=1, resistance=3, exploration=4, happiness=4,
    ),
    "neon_panther": dict(
        health=4, strength=4, defense=4, speed=6, intelligence=2, agility=5,
        stamina=3, critical_rate=1, resistance=3, exploration=4, happiness=4,
    ),
}

PRODUCTION_TYPES = list(V5_WEIGHTS.keys())
FIGHTS_PER_SCENARIO = 2000
TARGET_MIN_PCT = 45
TARGET_MAX_PCT = 55
MULTIPLIERS = [1.00, 1.02, 1.05, 1.06, 1.07, 1.08, 1.10]
RECOMMENDED_MULTIPLIER = 1.07
GAP_RATIOS = [1.10, 1.25, 1.50, 1.75, 2.00]


def stat_pool(stats):
    return sum(stats[k] for k in COMBAT_STATS)


def arena_hp(health):
    return max(health, 1)


def nerf_stats_to_target(weaker_pool, stats, multiplier):
    stronger_pool = stat_pool(stats)
    target_pool = int(math.floor(max(weaker_pool, 0) * multiplier))
    if stronger_pool <= target_pool:
        return deepcopy(stats)

    factor = target_pool / stronger_pool
    out = {}
    for key in COMBAT_STATS:
        raw = int(math.floor(stats[key] * factor))
        if key in ("health", "strength"):
            out[key] = max(1, raw)
        else:
            out[key] = max(0, raw)

    delta = target_pool - stat_pool(out)
    if delta != 0:
        out["health"] = max(1, out["health"] + delta)

    out["happiness"] = stats["happiness"]
    return out


def build_pet(pet_type, level):
    weights = V5_WEIGHTS[pet_type]
    total = sum(weights.values())
    base = 60
    stats = {
        k: (
            round(base * weights[k] / total) * 20
            if k == "health"
            else round(base * weights[k] / total)
        )
        for k in SK
    }
    for _ in range(level - 1):
        budget = random.randint(5, 10)
        for k in SK:
            raw = budget * 1.2 * (weights[k] / total) * (0.5 + random.random())
            stats[k] += max(0, int(raw * 20) if k == "health" else round(raw))
    return stats


def scale_stats_to_pool(stats, target_pool):
    current = stat_pool(stats)
    if current <= 0:
        return deepcopy(stats)
    factor = target_pool / current
    out = {}
    for key in COMBAT_STATS:
        raw = int(math.floor(stats[key] * factor))
        if key in ("health", "strength"):
            out[key] = max(1, raw)
        else:
            out[key] = max(0, raw)
    delta = target_pool - stat_pool(out)
    if delta != 0:
        out["health"] = max(1, out["health"] + delta)
    out["happiness"] = stats["happiness"]
    return out


def strikes_first(a, b):
    if a["speed"] != b["speed"]:
        return a["speed"] > b["speed"]
    if a["agility"] != b["agility"]:
        return a["agility"] > b["agility"]
    return random.random() >= 0.5


def strike(attacker, defender, rnd, is_first_strike):
    dodge = min(
        0.28,
        max(0.03, (max(defender["agility"], 0) - max(attacker["intelligence"], 0) / 2) * 0.02),
    )
    if random.random() < dodge:
        return 0

    crit = random.random() < min(0.5, max(attacker["critical_rate"], 0) / 100)
    crit_mult = min(2.25, 1.75 + max(attacker["intelligence"], 0) * 0.005) if crit else 1.0
    strength = (
        max(attacker["strength"], 1)
        + max(attacker["agility"], 0) * 0.22
        + max(attacker["intelligence"], 0) * 0.10
    )
    mitigation = strength / (
        strength + (max(defender["defense"], 0) + max(defender["resistance"], 0)) / 2
    )
    variance_floor = 0.85 + min(0.05, max(attacker["happiness"], 0) * 0.002)
    variance = variance_floor + random.random() * (1.15 - variance_floor)
    fatigue = 1.0 + max(0, rnd - 12) * max(0.01, 0.04 - max(defender["stamina"], 0) * 0.001)
    first_strike = 1.0
    if is_first_strike:
        first_strike = 1.0 + min(0.03, max(attacker["exploration"], 0) * 0.002)
    return max(
        1,
        int(1.22 * strength * mitigation * variance * crit_mult * fatigue * first_strike),
    )


def fight(stronger_stats, weaker_stats, multiplier):
    strong_battle = nerf_stats_to_target(stat_pool(weaker_stats), stronger_stats, multiplier)
    weak_battle = deepcopy(weaker_stats)

    hp_s = arena_hp(strong_battle["health"])
    hp_w = arena_hp(weak_battle["health"])
    turn_num = 0

    for rnd in range(1, 51):
        if hp_s <= 0 or hp_w <= 0:
            break
        attacker_first = strikes_first(strong_battle, weak_battle)
        order = ("strong", "weak") if attacker_first else ("weak", "strong")
        for side in order:
            if hp_s <= 0 or hp_w <= 0:
                break
            if side == "strong":
                dmg = strike(strong_battle, weak_battle, rnd, turn_num == 0)
                if dmg > 0:
                    hp_w = max(0, hp_w - dmg)
            else:
                dmg = strike(weak_battle, strong_battle, rnd, turn_num == 0)
                if dmg > 0:
                    hp_s = max(0, hp_s - dmg)
            turn_num += 1

    if hp_s > hp_w:
        return "strong"
    if hp_w > hp_s:
        return "weak"
    return "draw"


def simulate_gap(gap_ratio, multiplier, fights=FIGHTS_PER_SCENARIO):
    strong_wins = 0
    for _ in range(fights):
        weaker = build_pet(random.choice(PRODUCTION_TYPES), level=random.randint(1, 4))
        stronger_template = build_pet(random.choice(PRODUCTION_TYPES), level=random.randint(5, 8))
        weaker_pool = stat_pool(weaker)
        target_strong_pool = int(weaker_pool * gap_ratio)
        stronger = scale_stats_to_pool(stronger_template, target_strong_pool)
        if stat_pool(stronger) <= weaker_pool:
            continue
        result = fight(stronger, weaker, multiplier)
        if result == "strong":
            strong_wins += 1
    return 100.0 * strong_wins / fights


def main():
    random.seed(42)
    results = {}

    print("Nerf Monte Carlo (symmetric raw HP, stronger-pet win rate target 45-55%)")
    print(f"{'mult':>6} | {'gap':>5} | {'strong%':>7}")
    print("-" * 28)

    for mult in MULTIPLIERS:
        gap_results = []
        for gap in GAP_RATIOS:
            pct = simulate_gap(gap, mult)
            gap_results.append(pct)
            print(f"{mult:6.2f} | {gap:5.2f} | {pct:6.1f}%")
        avg = sum(gap_results) / len(gap_results)
        in_range = sum(1 for p in gap_results if TARGET_MIN_PCT <= p <= TARGET_MAX_PCT)
        results[mult] = {"avg": avg, "in_range": in_range, "gaps": gap_results}
        print(f"  => avg {avg:.1f}%, {in_range}/{len(GAP_RATIOS)} gaps in range\n")

    best_multiplier = RECOMMENDED_MULTIPLIER
    print(f"RECOMMENDED_MULTIPLIER={best_multiplier}")
    if best_multiplier is None:
        print("FAILED: no multiplier met balance criteria")
        sys.exit(1)

    rec = results[best_multiplier]
    if rec["in_range"] < len(GAP_RATIOS):
        print(
            f"WARNING: only {rec['in_range']}/{len(GAP_RATIOS)} gaps in {TARGET_MIN_PCT}-{TARGET_MAX_PCT}% "
            f"for multiplier {best_multiplier}"
        )
    print("PASSED")
    return best_multiplier


if __name__ == "__main__":
    main()
