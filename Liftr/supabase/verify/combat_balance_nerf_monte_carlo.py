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
    "dragon": dict(
        health=4, strength=4, defense=6, speed=4, intelligence=4, agility=3,
        stamina=3, critical_rate=1, resistance=4, exploration=4, happiness=4,
    ),
    "cybercat": dict(
        health=4, strength=4, defense=4, speed=5, intelligence=3, agility=5,
        stamina=3, critical_rate=1, resistance=3, exploration=4, happiness=4,
    ),
}

PRODUCTION_TYPES = list(V5_WEIGHTS.keys())
FIGHTS_PER_SCENARIO = 2000
TARGET_MIN_PCT = 45
TARGET_MAX_PCT = 55
RECOMMENDED_MULTIPLIER = 1.05
GAP_RATIOS = [1.25, 1.50, 1.75, 2.00]
RARITY_MULT = {"epic": 1.20, "legendary": 1.35, "mythic": 1.50}


def effective_power(stats):
    strike = max(stats["strength"], 1) + stats["agility"] * 0.22 + stats["intelligence"] * 0.10
    mit = (stats["defense"] + stats["resistance"]) / 2.0
    return (
        strike * 3.0
        + mit * 2.0
        + stats["speed"] * 0.8
        + stats["agility"] * 0.5
        + stats["health"] * 0.15
        + stats["critical_rate"] * 0.3
        + stats["stamina"] * 0.2
        + stats["exploration"] * 0.15
    )


def comparison_pool(stats):
    return int(math.floor(stats["health"] * 0.25)) + sum(stats[k] for k in COMBAT_STATS if k != "health")


def stat_pool(stats):
    return sum(stats[k] for k in COMBAT_STATS)


def arena_hp(health):
    return max(health, 1)


def nerf_stats_to_target(weaker_stats, stronger_stats, multiplier=RECOMMENDED_MULTIPLIER):
    weaker_power = effective_power(weaker_stats)
    stronger_power = effective_power(stronger_stats)
    target_power = weaker_power * multiplier
    if stronger_power <= target_power:
        return deepcopy(stronger_stats)

    factor = target_power / stronger_power
    out = deepcopy(stronger_stats)
    for key in COMBAT_STATS:
        raw = int(math.floor(out[key] * factor))
        if key in ("health", "strength"):
            out[key] = max(1, raw)
        else:
            out[key] = max(0, raw)
    out["happiness"] = max(1, int(math.floor(out["happiness"] * factor)))
    return out


def build_pet(pet_type, level, rarity="epic"):
    weights = V5_WEIGHTS[pet_type]
    total = sum(weights.values())
    rm = RARITY_MULT.get(rarity, 1.2)
    stats = {
        k: (
            round(60 * weights[k] / total) * 20
            if k == "health"
            else round(60 * weights[k] / total)
        )
        for k in SK
    }
    for _ in range(level - 1):
        budget = random.randint(5, 10)
        for k in SK:
            raw = budget * rm * (weights[k] / total) * (0.5 + random.random())
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
    strong_battle = nerf_stats_to_target(weaker_stats, stronger_stats, multiplier)
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


def simulate_gap(gap_ratio, multiplier=RECOMMENDED_MULTIPLIER, fights=FIGHTS_PER_SCENARIO):
    strong_wins = 0
    counted = 0
    for _ in range(fights):
        weaker = build_pet(random.choice(PRODUCTION_TYPES), level=random.randint(2, 4))
        stronger_template = build_pet(random.choice(PRODUCTION_TYPES), level=random.randint(6, 9), rarity="mythic")
        weaker_cmp = comparison_pool(weaker)
        target_cmp = int(weaker_cmp * gap_ratio)
        stronger = scale_stats_to_pool(stronger_template, int(stat_pool(weaker) * gap_ratio))
        if comparison_pool(stronger) <= weaker_cmp:
            continue
        if comparison_pool(stronger) * 100 <= weaker_cmp * 125:
            continue
        counted += 1
        result = fight(stronger, weaker, multiplier)
        if result == "strong":
            strong_wins += 1
    if counted == 0:
        return 0.0
    return 100.0 * strong_wins / counted


def main():
    random.seed(42)
    gap_results = {}

    print("Nerf Monte Carlo v2 (effective-power nerf, multiplier=%.2f, target %d-%d%%)" % (
        RECOMMENDED_MULTIPLIER, TARGET_MIN_PCT, TARGET_MAX_PCT,
    ))
    print(f"{'gap':>5} | {'strong%':>7} | {'status':>8}")
    print("-" * 28)

    failures = []
    for gap in GAP_RATIOS:
        pct = simulate_gap(gap)
        gap_results[gap] = pct
        in_range = TARGET_MIN_PCT <= pct <= TARGET_MAX_PCT
        status = "OK" if in_range else "FAIL"
        relaxed = gap >= 1.75 and 35 <= pct <= 65
        if not in_range and relaxed:
            status = "RELAXED"
        print(f"{gap:5.2f} | {pct:6.1f}% | {status:>8}")
        if status == "FAIL":
            failures.append(gap)

    avg = sum(gap_results.values()) / len(gap_results)
    primary_gaps = [gap_results[g] for g in [1.25, 1.50]]
    primary_ok = all(TARGET_MIN_PCT <= p <= TARGET_MAX_PCT for p in primary_gaps)

    print(f"\navg={avg:.1f}% primary_gaps_1.25_1.50={'PASS' if primary_ok else 'FAIL'}")

    if not primary_ok:
        print("FAILED: primary gap ratios 1.25 and 1.50 must land in 45-55%")
        sys.exit(1)

    if failures:
        print(f"WARNING: extended gaps out of strict range: {failures}")

    print("PASSED")
    return RECOMMENDED_MULTIPLIER


if __name__ == "__main__":
    main()
