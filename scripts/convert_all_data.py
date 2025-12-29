#!/usr/bin/env python3
"""
Convert all Binance raw kline data to zigQuant CSV format.

Binance raw format (12 columns):
1. Open time (ms)
2. Open
3. High
4. Low
5. Close
6. Volume
7. Close time
8. Quote asset volume
9. Number of trades
10. Taker buy base asset volume
11. Taker buy quote asset volume
12. Ignore

zigQuant format (6 columns):
timestamp,open,high,low,close,volume
"""

import os
import zipfile
import csv
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor, as_completed
import sys

# Configuration
RAW_DATA_DIR = Path(
    "/home/davirain/dev/zigQuant/data/binance_raw/data/spot/monthly/klines/BTCUSDT"
)
OUTPUT_DIR = Path("/home/davirain/dev/zigQuant/data")
SYMBOL = "BTCUSDT"

# All available timeframes (excluding 1s which is too large - handle separately with streaming)
TIMEFRAMES = [
    # "1s",  # Skip - too large, needs streaming conversion
    "1m",
    "3m",
    "5m",
    "15m",
    "30m",
    "1h",
    "2h",
    "4h",
    "6h",
    "8h",
    "12h",
    "1d",
]


def convert_timeframe(timeframe: str) -> dict:
    """Convert all data for a single timeframe."""
    tf_dir = RAW_DATA_DIR / timeframe
    if not tf_dir.exists():
        return {
            "timeframe": timeframe,
            "status": "error",
            "message": "Directory not found",
        }

    zip_files = sorted(tf_dir.glob("*.zip"))
    if not zip_files:
        return {
            "timeframe": timeframe,
            "status": "error",
            "message": "No zip files found",
        }

    output_file = OUTPUT_DIR / f"{SYMBOL}_{timeframe}_2017_2025.csv"

    all_rows = []
    processed_files = 0

    for zip_path in zip_files:
        try:
            with zipfile.ZipFile(zip_path, "r") as zf:
                # Get the CSV file inside the zip
                csv_files = [f for f in zf.namelist() if f.endswith(".csv")]
                if not csv_files:
                    continue

                with zf.open(csv_files[0]) as csv_file:
                    content = csv_file.read().decode("utf-8")
                    for line in content.strip().split("\n"):
                        if not line:
                            continue
                        parts = line.split(",")
                        if len(parts) >= 6:
                            # Extract: timestamp, open, high, low, close, volume
                            row = [
                                parts[0],  # timestamp (ms)
                                parts[1],  # open
                                parts[2],  # high
                                parts[3],  # low
                                parts[4],  # close
                                parts[5],  # volume
                            ]
                            all_rows.append(row)
                processed_files += 1
        except Exception as e:
            print(f"  Error processing {zip_path.name}: {e}", file=sys.stderr)

    if not all_rows:
        return {
            "timeframe": timeframe,
            "status": "error",
            "message": "No data extracted",
        }

    # Sort by timestamp
    all_rows.sort(key=lambda x: int(x[0]))

    # Remove duplicates (same timestamp)
    seen_timestamps = set()
    unique_rows = []
    for row in all_rows:
        ts = row[0]
        if ts not in seen_timestamps:
            seen_timestamps.add(ts)
            unique_rows.append(row)

    # Write output file
    with open(output_file, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "open", "high", "low", "close", "volume"])
        writer.writerows(unique_rows)

    file_size = output_file.stat().st_size
    return {
        "timeframe": timeframe,
        "status": "success",
        "files_processed": processed_files,
        "candles": len(unique_rows),
        "output_file": str(output_file),
        "file_size_mb": round(file_size / (1024 * 1024), 2),
    }


def main():
    print("=" * 60)
    print("Binance to zigQuant Data Converter")
    print("=" * 60)
    print(f"Raw data: {RAW_DATA_DIR}")
    print(f"Output: {OUTPUT_DIR}")
    print(f"Timeframes: {', '.join(TIMEFRAMES)}")
    print("=" * 60)

    # Ensure output directory exists
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    results = []

    # Process timeframes (can be parallelized, but let's do sequentially for progress visibility)
    for i, tf in enumerate(TIMEFRAMES, 1):
        print(f"\n[{i}/{len(TIMEFRAMES)}] Converting {tf}...", flush=True)
        result = convert_timeframe(tf)
        results.append(result)

        if result["status"] == "success":
            print(f"  ✓ {result['candles']:,} candles, {result['file_size_mb']} MB")
        else:
            print(f"  ✗ Error: {result.get('message', 'Unknown error')}")

    # Summary
    print("\n" + "=" * 60)
    print("CONVERSION SUMMARY")
    print("=" * 60)
    print(f"{'Timeframe':<10} {'Status':<10} {'Candles':>15} {'Size (MB)':>12}")
    print("-" * 60)

    total_candles = 0
    total_size = 0
    success_count = 0

    for r in results:
        if r["status"] == "success":
            print(
                f"{r['timeframe']:<10} {'OK':<10} {r['candles']:>15,} {r['file_size_mb']:>12}"
            )
            total_candles += r["candles"]
            total_size += r["file_size_mb"]
            success_count += 1
        else:
            print(f"{r['timeframe']:<10} {'FAILED':<10} {'-':>15} {'-':>12}")

    print("-" * 60)
    print(
        f"{'TOTAL':<10} {success_count}/{len(TIMEFRAMES):<8} {total_candles:>15,} {total_size:>12.2f}"
    )
    print("=" * 60)

    # List generated files
    print("\nGenerated files:")
    for f in sorted(OUTPUT_DIR.glob(f"{SYMBOL}_*_2017_2025.csv")):
        print(f"  {f}")


if __name__ == "__main__":
    main()
