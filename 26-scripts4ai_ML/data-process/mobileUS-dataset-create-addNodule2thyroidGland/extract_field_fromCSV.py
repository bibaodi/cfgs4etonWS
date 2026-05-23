#!/usr/bin/env python3
"""
Extract the first field ending with 'dcm_frms' from each row of a CSV file.
Usage: python extract_first_dcm_frms.py input.csv [output.txt]
If output file is omitted, results are printed to stdout.
"""

import csv
import sys

def extract_first_dcm_frms(input_file, output_file=None):
    with open(input_file, 'r', newline='') as infile:
        reader = csv.reader(infile)
        # Skip header (first row)
        header = next(reader, None)
        
        results = []
        results2 = []
        for row in reader:
            # Find all fields that end with 'dcm_frms'
            matching = [field for field in row if field.endswith('dcm_frms')]
            if matching:
                # Take only the first one
                results.append(matching[0])
            if len(matching)>1:
                results2.append(matching[1])

    
    # Write output
    if output_file:
        with open(output_file, 'w') as outfile:
            outfile.write('\n'.join(results) + '\n')
            outfile.write('-----------2-----')
            outfile.write('\n'.join(results2) + '\n')
    else:
        for line in results:
            print(line)
        for line in results2:
            print(line)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python extract_first_dcm_frms.py input.csv [output.txt]")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None
    extract_first_dcm_frms(input_file, output_file)
