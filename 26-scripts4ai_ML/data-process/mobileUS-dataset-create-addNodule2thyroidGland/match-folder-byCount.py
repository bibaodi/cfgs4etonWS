#!/usr/bin/env python3
"""
Match items from two lists by equal count and produce a CSV.
Usage: python match_counts.py file_A.txt file_B.txt [output.csv]
If output file is omitted, results are printed to stdout.
"""

import sys
import csv
from collections import defaultdict

def parse_file(filename):
    """Read file with lines 'name: count', return dict count -> list of names."""
    counts = defaultdict(list)
    with open(filename, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith('#'):  # skip empty lines and comments
                continue
            if ':' not in line:
                print(f"Warning: line {line_num} in {filename} has no colon, skipping: {line}", file=sys.stderr)
                continue
            name, count_str = line.split(':', 1)
            name = name.strip()
            count_str = count_str.strip()
            try:
                count = int(count_str)
            except ValueError:
                print(f"Warning: line {line_num} in {filename} has non-integer count, skipping: {line}", file=sys.stderr)
                continue
            counts[count].append(name)
    return counts

def main():
    if len(sys.argv) < 3:
        print("Usage: python match_counts.py file_A.txt file_B.txt [output.csv]")
        sys.exit(1)

    file_a = sys.argv[1]
    file_b = sys.argv[2]
    output_file = sys.argv[3] if len(sys.argv) > 3 else None

    # Parse both files
    a_counts = parse_file(file_a)
    b_counts = parse_file(file_b)

    # Find common counts
    common_counts = set(a_counts.keys()) & set(b_counts.keys())

    # Prepare rows for CSV
    rows = []
    for count in sorted(common_counts):
        for name_a in a_counts[count]:
            for name_b in b_counts[count]:
                rows.append([name_a, name_b, count])

    # Write output
    if output_file:
        with open(output_file, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['A', 'B', 'count'])  # optional header
            writer.writerows(rows)
    else:
        # Print to stdout as CSV
        writer = csv.writer(sys.stdout)
        writer.writerow(['A', 'B', 'count'])
        writer.writerows(rows)

if __name__ == '__main__':
    main()
