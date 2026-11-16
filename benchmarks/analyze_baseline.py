#!/usr/bin/env python3
"""
Baseline Benchmark Analysis & Ingestion Tool
Instagram Social Media Database (DBMS Project - Team T0145)
Author: Badal Khandelwal (badalkhandelwal346-ai)

Purpose:
  Reads the official benchmark outputs from `benchmarks/results/baseline/summary.csv`
  and raw plan files (`R01.txt` ... `W06.txt`), validates completeness across all 30 queries,
  computes summary metrics, identifies fastest/slowest queries, and safely updates the
  timing table and ranking sections in `docs/03_baseline_timings.md` without modifying
  manually authored analysis sections.

Usage:
  python3 benchmarks/analyze_baseline.py [--check-only] [--update-doc] [--csv PATH] [--plans-dir PATH] [--doc PATH]
"""

import os
import sys
import csv
import re
import argparse
from typing import Dict, List, Optional, Tuple

EXPECTED_QUERIES = [f"R{i:02d}" for i in range(1, 25)] + [f"W{i:02d}" for i in range(1, 7)]

QUERY_TITLES = {
    "R01": "Home feed: latest 30 posts from followed accounts",
    "R02": "Profile grid: user 217's latest 12 posts",
    "R03": "Open a profile by username",
    "R04": "Post page: top-level comments with reply counts",
    "R05": "Explore: top posts tagged #travel in June 2026",
    "R06": "Search bar: prefix/substring match accounts",
    "R07": "\"Liked by\": users liking post with follow status",
    "R08": "\"Suggested for you\": friends-of-friends graph traversal",
    "R09": "Follow requests screen: pending requests for account 338",
    "R10": "Story highlights: stories by followed accounts in June 2026",
    "R11": "Creator insights: engagement rate per follower (top 20)",
    "R12": "Trending: most used hashtags in late June 2026",
    "R13": "Creator tools: comments with zero replies",
    "R14": "\"Not following back\": followers not followed back",
    "R15": "Data quality: accounts with mismatched follower counts",
    "R16": "Places: posts tagged in Goa during June 2026",
    "R17": "Reels team: creator reels > 60s in 2026",
    "R18": "Content analytics: daily post volume by type in June 2026",
    "R19": "Verified-account report: last post and total likes",
    "R20": "Content analytics: top 10 most commented posts in June 2026",
    "R21": "Creator tools: ghost followers for user 217",
    "R22": "Moderation console: hidden comments paginated",
    "R23": "Like button state: check if user 1042 liked post",
    "R24": "Story insights: account story views in last 30 days",
    "W01": "Publish a new photo post",
    "W02": "Double-tap: user 1042 likes post 59689",
    "W03": "Synchronize post like counter after like",
    "W04": "Nightly batch job: reconcile follower counts",
    "W05": "Housekeeping: delete expired stories before June 2026",
    "W06": "Bulk accept pending follow requests for account 338",
}

def extract_individual_runs_from_plan(plan_file_path: str) -> List[float]:
    """Extract individual execution times (in ms) from raw plan file."""
    if not os.path.exists(plan_file_path):
        return []
    times = []
    with open(plan_file_path, "r", encoding="utf-8") as f:
        content = f.read()
    # Matches 'Execution Time: 12.345 ms'
    matches = re.findall(r"Execution Time:\s*([0-9.]+)\s*ms", content)
    for m in matches:
        try:
            times.append(float(m))
        except ValueError:
            pass
    return times

def parse_summary_csv(csv_path: str, plans_dir: Optional[str] = None) -> Tuple[Dict[str, dict], List[str]]:
    """Parse benchmarks/results/baseline/summary.csv and validate all expected queries."""
    if not os.path.exists(csv_path):
        return {}, [f"Summary CSV file not found at: {csv_path}"]

    results = {}
    errors = []

    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        required_cols = {"query_id", "type", "avg_ms", "median_ms", "min_ms", "max_ms", "scan_nodes"}
        if not required_cols.issubset(set(reader.fieldnames or [])):
            missing = required_cols - set(reader.fieldnames or [])
            errors.append(f"CSV header is missing required columns: {missing}")
            return {}, errors

        for row_idx, row in enumerate(reader, start=2):
            qid = row["query_id"].strip()
            try:
                avg_ms = float(row["avg_ms"])
                med_ms = float(row["median_ms"])
                min_ms = float(row["min_ms"])
                max_ms = float(row["max_ms"])
            except ValueError as e:
                errors.append(f"Line {row_idx}: Non-numeric timing value for query {qid}: {e}")
                continue

            qtype = row["type"].strip()
            scan_nodes = row["scan_nodes"].strip()

            # Inspect raw plans if available to fetch run 1, run 2, run 3
            runs = []
            if plans_dir and os.path.isdir(plans_dir):
                plan_file = os.path.join(plans_dir, f"{qid}.txt")
                runs = extract_individual_runs_from_plan(plan_file)

            results[qid] = {
                "query_id": qid,
                "type": qtype,
                "avg_ms": avg_ms,
                "median_ms": med_ms,
                "min_ms": min_ms,
                "max_ms": max_ms,
                "scan_nodes": scan_nodes,
                "runs": runs,
            }

    # Verify presence of all 30 queries
    missing_queries = [qid for qid in EXPECTED_QUERIES if qid not in results]
    if missing_queries:
        errors.append(f"Missing {len(missing_queries)} query result(s) in CSV: {', '.join(missing_queries)}")

    return results, errors

def generate_markdown_table(results: Dict[str, dict]) -> str:
    """Generate Markdown timing table matching the required CP2 format."""
    lines = [
        "| Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Median (ms) | Min (ms) | Max (ms) | Scan Type |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|---|",
    ]

    total_avg = 0.0
    valid_count = 0

    for qid in EXPECTED_QUERIES:
        if qid in results:
            r = results[qid]
            title = QUERY_TITLES.get(qid, "")
            runs = r.get("runs", [])
            r1 = f"{runs[0]:.3f}" if len(runs) >= 1 else "-"
            r2 = f"{runs[1]:.3f}" if len(runs) >= 2 else "-"
            r3 = f"{runs[2]:.3f}" if len(runs) >= 3 else "-"
            avg_str = f"{r['avg_ms']:.3f}"
            med_str = f"{r['median_ms']:.3f}"
            min_str = f"{r['min_ms']:.3f}"
            max_str = f"{r['max_ms']:.3f}"
            scan_str = r["scan_nodes"]
            lines.append(f"| **{qid}**: {title} | {r['type']} | {r1} | {r2} | {r3} | **{avg_str}** | {med_str} | {min_str} | {max_str} | `{scan_str}` |")
            total_avg += r["avg_ms"]
            valid_count += 1
        else:
            title = QUERY_TITLES.get(qid, "")
            qtype = "READ" if qid.startswith("R") else "WRITE"
            lines.append(f"| **{qid}**: {title} | {qtype} | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |")

    if valid_count == len(EXPECTED_QUERIES):
        lines.append(f"| **Total Workload (Sum of all 30)** | **ALL** | — | — | — | **{total_avg:.3f}** | — | — | — | — |")
    else:
        lines.append("| **Total Workload (Sum of all 30)** | **ALL** | — | — | — | *PENDING* | — | — | — | — |")

    return "\n".join(lines)

def generate_rankings_markdown(results: Dict[str, dict]) -> str:
    """Generate top 5 slowest and top 5 fastest query rankings."""
    if len(results) < len(EXPECTED_QUERIES):
        return (
            "> [!NOTE]\n"
            "> **Awaiting Official Benchmark Execution**\n"
            "> Complete rankings will be computed automatically once Atharv runs the benchmark on the shared database.\n"
        )

    sorted_queries = sorted(results.values(), key=lambda x: x["avg_ms"], reverse=True)
    slowest_5 = sorted_queries[:5]
    fastest_5 = sorted(results.values(), key=lambda x: x["avg_ms"])[:5]

    lines = [
        "### Top 5 Slowest Baseline Queries (Primary Bottlenecks)",
        "",
        "| Rank | Query | Category | Avg Time (ms) | Primary Scan Nodes | Root Cause Bottleneck |",
        "|:---:|---|---|---:|---|---|",
    ]
    for idx, q in enumerate(slowest_5, 1):
        lines.append(f"| {idx} | **{q['query_id']}** ({QUERY_TITLES.get(q['query_id'], '')}) | {q['type']} | {q['avg_ms']:.3f} | `{q['scan_nodes']}` | Full unindexed sequential scans / hash joins |")

    lines.extend([
        "",
        "### Top 5 Fastest Baseline Queries",
        "",
        "| Rank | Query | Category | Avg Time (ms) | Primary Scan Nodes | Efficiency Factor |",
        "|:---:|---|---|---:|---|---|",
    ])
    for idx, q in enumerate(fastest_5, 1):
        lines.append(f"| {idx} | **{q['query_id']}** ({QUERY_TITLES.get(q['query_id'], '')}) | {q['type']} | {q['avg_ms']:.3f} | `{q['scan_nodes']}` | Primary key / Unique index scan or small table lookup |")

    return "\n".join(lines)

def update_documentation_file(doc_path: str, results: Dict[str, dict]) -> bool:
    """Update `docs/03_baseline_timings.md` between demarcation comments."""
    if not os.path.exists(doc_path):
        print(f"Error: Target documentation file {doc_path} does not exist.", file=sys.stderr)
        return False

    with open(doc_path, "r", encoding="utf-8") as f:
        doc_content = f.read()

    table_start_tag = "<!-- BENCHMARK_TABLE_START -->"
    table_end_tag = "<!-- BENCHMARK_TABLE_END -->"
    rankings_start_tag = "<!-- RANKINGS_START -->"
    rankings_end_tag = "<!-- RANKINGS_END -->"

    if table_start_tag not in doc_content or table_end_tag not in doc_content:
        print(f"Error: Demarcation comments {table_start_tag} ... {table_end_tag} not found in {doc_path}.", file=sys.stderr)
        return False

    table_markdown = generate_markdown_table(results)
    pattern_table = re.compile(rf"{re.escape(table_start_tag)}.*?{re.escape(table_end_tag)}", re.DOTALL)
    new_doc_content = pattern_table.sub(f"{table_start_tag}\n{table_markdown}\n{table_end_tag}", doc_content)

    if rankings_start_tag in new_doc_content and rankings_end_tag in new_doc_content:
        rankings_markdown = generate_rankings_markdown(results)
        pattern_rankings = re.compile(rf"{re.escape(rankings_start_tag)}.*?{re.escape(rankings_end_tag)}", re.DOTALL)
        new_doc_content = pattern_rankings.sub(f"{rankings_start_tag}\n{rankings_markdown}\n{rankings_end_tag}", new_doc_content)

    with open(doc_path, "w", encoding="utf-8") as f:
        f.write(new_doc_content)

    return True

def main():
    parser = argparse.ArgumentParser(description="Analyze Instagram Baseline Benchmarks")
    parser.add_argument("--csv", default="benchmarks/results/baseline/summary.csv", help="Path to summary.csv")
    parser.add_argument("--plans-dir", default="benchmarks/results/baseline", help="Path to directory containing raw plan txt files")
    parser.add_argument("--doc", default="docs/03_baseline_timings.md", help="Path to docs/03_baseline_timings.md")
    parser.add_argument("--check-only", action="store_true", help="Only validate benchmark files without altering documentation")
    parser.add_argument("--update-doc", action="store_true", help="Update the timing table in docs/03_baseline_timings.md")

    args = parser.parse_args()

    print("=== Instagram DBMS: Baseline Benchmark Ingestion Utility ===")
    print(f"Summary CSV: {args.csv}")
    print(f"Plans Directory: {args.plans_dir}")
    print(f"Target Documentation: {args.doc}")

    if not os.path.exists(args.csv):
        print(f"\n[INFO] Benchmark results summary not yet found at: {args.csv}")
        print("[INFO] Official benchmark results are pending execution by Atharv.")
        print("[INFO] The framework is in place and ready for automatic ingestion upon benchmark completion.")
        sys.exit(0)

    results, errors = parse_summary_csv(args.csv, args.plans_dir)
    if errors:
        print("\n[VALIDATION WARNINGS / ERRORS]:")
        for err in errors:
            print(f"  - {err}")

    print(f"\nSuccessfully parsed {len(results)}/{len(EXPECTED_QUERIES)} query results.")

    if args.update_doc:
        print(f"Updating {args.doc}...")
        success = update_documentation_file(args.doc, results)
        if success:
            print("[SUCCESS] Documentation updated successfully.")
        else:
            print("[ERROR] Failed to update documentation.", file=sys.stderr)
            sys.exit(1)

if __name__ == "__main__":
    main()
