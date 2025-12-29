#!/usr/bin/env python3
"""
Streaming converter for 1s Binance data to zigQuant CSV format.

This script handles the massive 1s dataset (~258 million candles, ~21GB)
by processing files one at a time and writing directly to output,
avoiding memory issues.
"""

import os
import zipfile
from pathlib import Path
import sys
import time

# Configuration
RAW_DATA_DIR = Path(
    "/home/davirain/dev/zigQuant/data/binance_raw/data/spot/monthly/klines/BTCUSDT/1s"
)
OUTPUT_FILE = Path("/home/davirain/dev/zigQuant/data/BTCUSDT_1s_2017_2025.csv")
SYMBOL = "BTCUSDT"


def format_size(bytes_size):
    """Format bytes to human readable string."""
    for unit in ["B", "KB", "MB", "GB"]:
        if bytes_size < 1024:
            return f"{bytes_size:.2f} {unit}"
        bytes_size /= 1024
    return f"{bytes_size:.2f} TB"


def format_time(seconds):
    """Format seconds to human readable string."""
    if seconds < 60:
        return f"{seconds:.1f}s"
    elif seconds < 3600:
        return f"{seconds // 60:.0f}m {seconds % 60:.0f}s"
    else:
        return f"{seconds // 3600:.0f}h {(seconds % 3600) // 60:.0f}m"


def main():
    print("=" * 70)
    print("1s Data Streaming Converter")
    print("=" * 70)
    print(f"Input:  {RAW_DATA_DIR}")
    print(f"Output: {OUTPUT_FILE}")
    print("=" * 70)

    if not RAW_DATA_DIR.exists():
        print(f"ERROR: Directory not found: {RAW_DATA_DIR}")
        return 1

    # Get all zip files sorted by name (chronological order)
    zip_files = sorted(RAW_DATA_DIR.glob("*.zip"))
    total_files = len(zip_files)

    if total_files == 0:
        print("ERROR: No zip files found")
        return 1

    print(f"Found {total_files} zip files to process")
    print("=" * 70)

    start_time = time.time()
    total_candles = 0
    last_timestamp = None
    duplicates_skipped = 0

    # Open output file for writing
    with open(OUTPUT_FILE, "w") as outfile:
        # Write header
        outfile.write("timestamp,open,high,low,close,volume\n")

        for i, zip_path in enumerate(zip_files, 1):
            file_start = time.time()
            file_candles = 0
            file_duplicates = 0

            try:
                with zipfile.ZipFile(zip_path, "r") as zf:
                    # Get the CSV file inside the zip
                    csv_files = [f for f in zf.namelist() if f.endswith(".csv")]
                    if not csv_files:
                        print(
                            f"  [{i}/{total_files}] {zip_path.name}: No CSV found, skipping"
                        )
                        continue

                    with zf.open(csv_files[0]) as csv_file:
                        for line in csv_file:
                            line = line.decode("utf-8").strip()
                            if not line:
                                continue

                            parts = line.split(",")
                            if len(parts) >= 6:
                                timestamp = parts[0]

                                # Skip duplicates (same timestamp as last)
                                if timestamp == last_timestamp:
                                    file_duplicates += 1
                                    continue

                                last_timestamp = timestamp

                                # Write: timestamp,open,high,low,close,volume
                                outfile.write(
                                    f"{parts[0]},{parts[1]},{parts[2]},{parts[3]},{parts[4]},{parts[5]}\n"
                                )
                                file_candles += 1

                total_candles += file_candles
                duplicates_skipped += file_duplicates

                # Progress update
                elapsed = time.time() - start_time
                file_time = time.time() - file_start
                rate = total_candles / elapsed if elapsed > 0 else 0

                # Estimate remaining time
                remaining_files = total_files - i
                avg_time_per_file = elapsed / i
                eta = remaining_files * avg_time_per_file

                print(
                    f"  [{i:3d}/{total_files}] {zip_path.name}: "
                    f"{file_candles:,} candles ({file_time:.1f}s) | "
                    f"Total: {total_candles:,} | "
                    f"ETA: {format_time(eta)}"
                )

            except Exception as e:
                print(f"  [{i}/{total_files}] {zip_path.name}: ERROR - {e}")

    # Final stats
    end_time = time.time()
    total_time = end_time - start_time
    file_size = OUTPUT_FILE.stat().st_size

    print("=" * 70)
    print("CONVERSION COMPLETE")
    print("=" * 70)
    print(f"Total candles:      {total_candles:,}")
    print(f"Duplicates skipped: {duplicates_skipped:,}")
    print(f"Output file:        {OUTPUT_FILE}")
    print(f"File size:          {format_size(file_size)}")
    print(f"Total time:         {format_time(total_time)}")
    print(f"Average rate:       {total_candles / total_time:,.0f} candles/sec")
    print("=" * 70)

    return 0


if __name__ == "__main__":
    sys.exit(main())
