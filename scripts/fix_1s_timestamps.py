#!/usr/bin/env python3
"""
Fix 1s data timestamps - convert 16-digit microsecond timestamps to 13-digit millisecond timestamps.

Binance changed their timestamp format for 1s data starting from 2025-01-01:
- Before 2025: 13-digit milliseconds (e.g., 1706147569000)
- From 2025: 16-digit microseconds (e.g., 1735689600000000)

This script converts all timestamps to consistent 13-digit millisecond format.
"""

import sys
import time
from pathlib import Path

INPUT_FILE = Path("/home/davirain/dev/zigQuant/data/BTCUSDT_1s_2017_2025.csv")
OUTPUT_FILE = Path("/home/davirain/dev/zigQuant/data/BTCUSDT_1s_2017_2025_fixed.csv")


def format_time(seconds):
    if seconds < 60:
        return f"{seconds:.1f}s"
    elif seconds < 3600:
        return f"{seconds // 60:.0f}m {seconds % 60:.0f}s"
    else:
        return f"{seconds // 3600:.0f}h {(seconds % 3600) // 60:.0f}m"


def main():
    print("=" * 70)
    print("1s Data Timestamp Fixer")
    print("=" * 70)
    print(f"Input:  {INPUT_FILE}")
    print(f"Output: {OUTPUT_FILE}")
    print("=" * 70)

    start_time = time.time()
    total_lines = 0
    fixed_lines = 0

    with open(INPUT_FILE, "r") as infile, open(OUTPUT_FILE, "w") as outfile:
        for line in infile:
            total_lines += 1

            # Progress update every 10 million lines
            if total_lines % 10000000 == 0:
                elapsed = time.time() - start_time
                rate = total_lines / elapsed
                print(f"  Processed {total_lines:,} lines... ({rate:,.0f} lines/sec)")

            # Header line
            if total_lines == 1:
                outfile.write(line)
                continue

            parts = line.strip().split(",")
            if len(parts) >= 6:
                timestamp = parts[0]

                # If timestamp is 16 digits (microseconds), convert to 13 digits (milliseconds)
                if len(timestamp) == 16:
                    # Remove last 3 digits (convert microseconds to milliseconds)
                    parts[0] = timestamp[:-3]
                    fixed_lines += 1

                outfile.write(",".join(parts) + "\n")
            else:
                outfile.write(line)

    elapsed = time.time() - start_time

    print("=" * 70)
    print("TIMESTAMP FIX COMPLETE")
    print("=" * 70)
    print(f"Total lines:     {total_lines:,}")
    print(f"Fixed lines:     {fixed_lines:,}")
    print(f"Output file:     {OUTPUT_FILE}")
    print(f"Total time:      {format_time(elapsed)}")
    print("=" * 70)

    # Replace original file with fixed file
    print("\nReplacing original file with fixed file...")
    INPUT_FILE.unlink()
    OUTPUT_FILE.rename(INPUT_FILE)
    print(f"Done! Fixed file saved as: {INPUT_FILE}")


if __name__ == "__main__":
    main()
