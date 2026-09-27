#!/usr/bin/env python3
"""Summarise playtest logs (M10) against PLAN.md §6.1 (beat sheet) and §6.2 (acceptance).

Each playtester's game appends runs to user://playtest.csv (see scripts/game/playtest_logger.gd
for where that lives). Collect the files and run:

    python3 tools/playtest/summarize.py alice.csv bob.csv carol.csv [--min-fps 30] [--all]

Only runs that reached the victory screen count toward the verdicts, unless --all is given
(abandoned runs are still listed). Standard library only.
"""

from __future__ import annotations

import argparse
import csv
import statistics
import sys
from collections import OrderedDict
from pathlib import Path

BEATS = ["approach", "courtyard", "breather", "sanctum"]
# Target seconds per beat from the §6.1 beat sheet (title and victory screens aren't play time).
BEAT_TARGETS = {"approach": 150, "courtyard": 210, "breather": 30, "sanctum": 150}
TOTAL_MINUTES = (8.0, 12.0)      # §6.2: a first-time player finishes in 8–12 minutes
MAX_DEATHS = 5                   # §6.2: fewer than 5 deaths
HITCH_MS = 50.0                  # §6.2: no hitch over 50 ms


def load_runs(paths: list[Path]) -> "OrderedDict[str, dict]":
    """Runs keyed by run id: {"file", "outcome", "renderer", "quality", "beats": {beat: row}}."""
    runs: "OrderedDict[str, dict]" = OrderedDict()
    for path in paths:
        with path.open(newline="", encoding="utf-8") as handle:
            for row in csv.DictReader(handle):
                run = runs.setdefault(row["run"], {
                    "file": path.name, "outcome": row["outcome"], "platform": row["platform"],
                    "renderer": row["renderer"], "quality": row["quality"], "beats": {},
                })
                run["beats"][row["beat"]] = row
    return runs


def num(row: dict | None, key: str) -> float:
    return float(row[key]) if row and row.get(key) not in (None, "") else 0.0


def median(values: list[float]) -> float:
    return statistics.median(values) if values else 0.0


def verdict(ok: bool) -> str:
    return "PASS" if ok else "FAIL"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("csv", nargs="+", type=Path, help="playtest.csv files")
    parser.add_argument("--min-fps", type=float, default=30.0,
                        help="frame-rate floor for the verdict (D5: 60 on a discrete GPU, 30 on the laptop)")
    parser.add_argument("--all", action="store_true", help="count runs that didn't reach victory too")
    args = parser.parse_args()

    runs = load_runs(args.csv)
    if not runs:
        print("No runs found.")
        return 1

    print(f"{'run':<24} {'file':<16} {'outcome':<8} {'quality':<7} {'min':>5} {'deaths':>6} {'parries':>7} {'fps':>5} {'worst ms':>8} {'hitches':>7}")
    for run_id, run in runs.items():
        total = run["beats"].get("total")
        print(f"{run_id:<24} {run['file'][:16]:<16} {run['outcome']:<8} {run['quality']:<7} "
              f"{num(total, 'seconds') / 60:>5.1f} {num(total, 'deaths'):>6.0f} {num(total, 'parries'):>7.0f} "
              f"{num(total, 'avg_fps'):>5.0f} {num(total, 'worst_frame_ms'):>8.0f} {num(total, 'hitches'):>7.0f}")

    counted = [run for run in runs.values() if args.all or run["outcome"] == "victory"]
    print(f"\n{len(counted)} of {len(runs)} runs counted ({'all' if args.all else 'victories only'}).")
    if not counted:
        return 1

    print(f"\n{'beat':<10} {'target s':>8} {'median s':>8} {'Δ':>6} {'deaths':>6} {'attempts':>8} {'min fps':>7} {'hitches':>7}")
    for beat in BEATS:
        rows = [run["beats"].get(beat) for run in counted if beat in run["beats"]]
        seconds = median([num(row, "seconds") for row in rows])
        print(f"{beat:<10} {BEAT_TARGETS[beat]:>8} {seconds:>8.0f} {seconds - BEAT_TARGETS[beat]:>+6.0f} "
              f"{median([num(row, 'deaths') for row in rows]):>6.1f} {median([num(row, 'attempts') for row in rows]):>8.1f} "
              f"{min((num(row, 'avg_fps') for row in rows), default=0):>7.0f} {sum(num(row, 'hitches') for row in rows):>7.0f}")

    totals = [run["beats"].get("total") for run in counted]
    minutes = median([num(row, "seconds") / 60 for row in totals])
    deaths = median([num(row, "deaths") for row in totals])
    worst = max(num(row, "worst_frame_ms") for row in totals)
    fps = min(num(row, "avg_fps") for row in totals)
    print("\n§6.2 acceptance (median of the counted runs)")
    print(f"  {verdict(TOTAL_MINUTES[0] <= minutes <= TOTAL_MINUTES[1])}  finish in {TOTAL_MINUTES[0]:.0f}–{TOTAL_MINUTES[1]:.0f} min: {minutes:.1f} min")
    print(f"  {verdict(deaths < MAX_DEATHS)}  fewer than {MAX_DEATHS} deaths: {deaths:.1f}")
    print(f"  {verdict(worst <= HITCH_MS)}  no hitch over {HITCH_MS:.0f} ms: worst {worst:.0f} ms")
    print(f"  {verdict(fps >= args.min_fps)}  average FPS at least {args.min_fps:.0f} in every run: lowest {fps:.0f}")
    if len(counted) < 3:
        print("  NOTE  §6.2 asks for the median of 3 playtests.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
