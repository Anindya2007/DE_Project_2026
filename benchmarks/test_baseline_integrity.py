#!/usr/bin/env python3
"""
Baseline Timing & Benchmark Integrity Test Suite
Instagram Social Media Database (DBMS Project - Team T0145)
Author: Badal Khandelwal (badalkhandelwal346-ai)

Purpose:
  Mathematically validates all 30 query benchmark entries against raw plans,
  verifies statistical metrics (average, median, min, max), verifies rankings,
  and asserts consistency between `summary.csv` and `docs/03_baseline_timings.md`.
"""

import os
import sys
import csv
import re
import unittest
from typing import Dict, List

EXPECTED_QUERIES = [f"R{i:02d}" for i in range(1, 25)] + [f"W{i:02d}" for i in range(1, 7)]

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS_DIR = os.path.join(BASE_DIR, "benchmarks", "results", "baseline")
SUMMARY_CSV = os.path.join(RESULTS_DIR, "summary.csv")
TIMINGS_DOC = os.path.join(BASE_DIR, "docs", "03_baseline_timings.md")


class TestBaselineTimingIntegrity(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.summary_data: Dict[str, dict] = {}
        cls.assertTrue(os.path.exists(SUMMARY_CSV), f"Missing summary file: {SUMMARY_CSV}")
        cls.assertTrue(os.path.exists(TIMINGS_DOC), f"Missing documentation file: {TIMINGS_DOC}")

        with open(SUMMARY_CSV, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                qid = row["query_id"].strip()
                cls.summary_data[qid] = {
                    "type": row["type"].strip(),
                    "run1_ms": float(row["run1_ms"]),
                    "run2_ms": float(row["run2_ms"]),
                    "run3_ms": float(row["run3_ms"]),
                    "avg_ms": float(row["avg_ms"]),
                    "median_ms": float(row["median_ms"]),
                    "min_ms": float(row["min_ms"]),
                    "max_ms": float(row["max_ms"]),
                    "scan_nodes": row["scan_nodes"].strip(),
                }

    def test_01_all_30_queries_present_in_summary(self):
        """Verify all 30 queries (R01-R24, W01-W06) exist in summary.csv."""
        for qid in EXPECTED_QUERIES:
            self.assertIn(qid, self.summary_data, f"Query {qid} missing from summary.csv")
        self.assertEqual(len(self.summary_data), 30, "Expected exactly 30 query entries in summary.csv")

    def test_02_raw_plan_files_exist_and_have_three_runs(self):
        """Verify each query has a corresponding raw plan file with 3 runs."""
        for qid in EXPECTED_QUERIES:
            plan_file = os.path.join(RESULTS_DIR, f"{qid}.txt")
            self.assertTrue(os.path.exists(plan_file), f"Raw plan file missing: {plan_file}")
            with open(plan_file, "r", encoding="utf-8") as f:
                content = f.read()
            for r in (1, 2, 3):
                self.assertIn(f"=== {qid} run {r} ===", content, f"Missing run {r} marker in {qid}.txt")
            times = re.findall(r"Execution Time:\s*([0-9.]+)\s*ms", content)
            self.assertEqual(len(times), 3, f"{qid}.txt expected exactly 3 execution times, found {len(times)}")

    def test_03_summary_matches_raw_plan_times(self):
        """Verify summary.csv timings match parsed values from raw plan logs within tolerance."""
        for qid in EXPECTED_QUERIES:
            plan_file = os.path.join(RESULTS_DIR, f"{qid}.txt")
            with open(plan_file, "r", encoding="utf-8") as f:
                content = f.read()
            raw_times = [float(t) for t in re.findall(r"Execution Time:\s*([0-9.]+)\s*ms", content)]
            csv_times = [
                self.summary_data[qid]["run1_ms"],
                self.summary_data[qid]["run2_ms"],
                self.summary_data[qid]["run3_ms"],
            ]
            for r_idx, (r_raw, r_csv) in enumerate(zip(raw_times, csv_times), start=1):
                self.assertAlmostEqual(r_raw, r_csv, places=3,
                                      msg=f"{qid} Run {r_idx} mismatch between plan ({r_raw}) and CSV ({r_csv})")

    def test_04_mathematical_metrics_consistency(self):
        """Validate average, median, min, max calculations."""
        for qid, data in self.summary_data.items():
            runs = [data["run1_ms"], data["run2_ms"], data["run3_ms"]]
            calc_avg = round(sum(runs) / 3.0, 3)
            sorted_runs = sorted(runs)
            calc_med = sorted_runs[1]
            calc_min = sorted_runs[0]
            calc_max = sorted_runs[2]

            self.assertAlmostEqual(data["avg_ms"], calc_avg, delta=0.005,
                                  msg=f"{qid} average mismatch: reported {data['avg_ms']} vs calculated {calc_avg}")
            self.assertAlmostEqual(data["median_ms"], calc_med, delta=0.005,
                                  msg=f"{qid} median mismatch: reported {data['median_ms']} vs calculated {calc_med}")
            self.assertAlmostEqual(data["min_ms"], calc_min, delta=0.005,
                                  msg=f"{qid} min mismatch: reported {data['min_ms']} vs calculated {calc_min}")
            self.assertAlmostEqual(data["max_ms"], calc_max, delta=0.005,
                                  msg=f"{qid} max mismatch: reported {data['max_ms']} vs calculated {calc_max}")

    def test_05_documentation_table_consistency(self):
        """Verify docs/03_baseline_timings.md reflects exact summary.csv timings."""
        with open(TIMINGS_DOC, "r", encoding="utf-8") as f:
            doc_content = f.read()

        # Ensure no pending markers remain in the benchmark table
        table_match = re.search(r"<!-- BENCHMARK_TABLE_START -->(.*?)<!-- BENCHMARK_TABLE_END -->", doc_content, re.DOTALL)
        self.assertIsNotNone(table_match, "Benchmark table section missing in docs/03_baseline_timings.md")
        table_text = table_match.group(1)
        self.assertNotIn("*PENDING*", table_text, "Benchmark table still contains *PENDING* values")

        for qid, data in self.summary_data.items():
            self.assertIn(f"**{qid}**", table_text, f"Query {qid} missing from documentation table")
            self.assertIn(f"**{data['avg_ms']:.3f}**", table_text, f"Query {qid} average mismatch in doc table")

    def test_06_rankings_consistency(self):
        """Verify Top 5 Slowest and Top 5 Fastest rankings in documentation."""
        sorted_by_avg = sorted(self.summary_data.items(), key=lambda x: x[1]["avg_ms"], reverse=True)
        top_slowest = [x[0] for x in sorted_by_avg[:5]]
        top_fastest = [x[0] for x in sorted_by_avg[-5:]][::-1]

        self.assertEqual(top_slowest, ["R19", "W04", "R15", "R13", "R04"],
                         f"Slowest 5 queries mismatch: {top_slowest}")
        self.assertEqual(top_fastest, ["R03", "R23", "R08", "W01", "W03"],
                         f"Fastest 5 queries mismatch: {top_fastest}")


if __name__ == "__main__":
    print("=" * 70)
    print("INSTAGRAM DBMS: BASELINE TIMING & INTEGRITY TEST SUITE")
    print("=" * 70)
    suite = unittest.TestLoader().loadTestsFromTestCase(TestBaselineTimingIntegrity)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
