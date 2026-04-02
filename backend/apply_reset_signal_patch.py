#!/usr/bin/env python3
"""
Apply reset signal patch to Verilog files.

This script modifies the RST_N signals in module instantiations:
1. In mkBsvTop.v: mkBsvTopOnlyHardIp instance
2. In mkQpMrPgtQpc.v: mkSqGroup and mkRqGroup instances

The modifications are based on context patterns rather than absolute line numbers
to handle potential file changes.
"""

import argparse
import os
import re
import sys


def find_file(directory: str, filename: str) -> str | None:
    """Find a file in the specified directory (non-recursive)."""
    file_path = os.path.join(directory, filename)
    if os.path.isfile(file_path):
        return file_path
    return None


def patch_mkBsvTop(file_path: str) -> bool:
    """
    Patch mkBsvTop.v file.

    Find mkBsvTopOnlyHardIp module instantiation and change:
    .RST_N(RST_N) -> .RST_N(RST_N_partitionReset)

    Pattern used: Look for "mkBsvTopOnlyHardIp bsvTopOnlyHardIp" followed by
    .RST_N(RST_N) within the module instantiation.
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return False

    # Pattern to find mkBsvTopOnlyHardIp instantiation with .RST_N(RST_N)
    # We need to match the specific .RST_N that belongs to this module instance,
    # not .RST_N_ftileRst or other variants.
    # The pattern looks for the module instantiation line followed by .RST_N(RST_N)
    # that is NOT .RST_N_ftileRst

    # Strategy: Find the line with "mkBsvTopOnlyHardIp bsvTopOnlyHardIp"
    # Then find .RST_N(RST_N) that appears after it (before the semicolon ending the instance)

    lines = content.split('\n')
    modified = False
    i = 0
    while i < len(lines):
        line = lines[i]
        # Look for the module instantiation start
        if re.search(r'mkBsvTopOnlyHardIp\s+bsvTopOnlyHardIp\s*\(', line):
            # Found the instantiation, now find .RST_N(RST_N) within it
            # The instantiation ends with ");" on its own line or at the end of a line
            j = i
            while j < len(lines):
                current_line = lines[j]
                # Check for .RST_N(RST_N) - exact match, not .RST_N_something
                if re.search(r'\.RST_N\(RST_N\)', current_line):
                    # Make sure this is not .RST_N_ftileRst or similar
                    # by checking the line doesn't have RST_N followed by underscore before the paren
                    if not re.search(r'\.RST_N_\w+\(', current_line):
                        lines[j] = re.sub(r'\.RST_N\(RST_N\)', '.RST_N(RST_N_partitionReset)', current_line)
                        print(f"  Patched .RST_N in mkBsvTopOnlyHardIp at line {j + 1}")
                        modified = True
                        break
                # Check if we've reached the end of the instantiation
                if ');' in current_line and j > i:
                    break
                j += 1
        i += 1

    if modified:
        try:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write('\n'.join(lines))
            print(f"Successfully patched {file_path}")
        except Exception as e:
            print(f"Error writing {file_path}: {e}")
            return False

    return modified


def patch_mkQpMrPgtQpc(file_path: str) -> bool:
    """
    Patch mkQpMrPgtQpc.v file.

    Find mkSqGroup and mkRqGroup module instantiations and change:
    .RST_N(RST_N) -> .RST_N(RST_N_partitionReset)

    Pattern used: Look for "mkSqGroup sqGroup" and "mkRqGroup rqGroup" followed by
    .RST_N(RST_N) within each module instantiation.
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return False

    lines = content.split('\n')
    modified = False

    # Process mkSqGroup
    i = 0
    while i < len(lines):
        line = lines[i]
        if re.search(r'mkSqGroup\s+sqGroup\s*\(', line):
            j = i
            while j < len(lines):
                current_line = lines[j]
                if re.search(r'\.RST_N\(RST_N\)', current_line):
                    lines[j] = re.sub(r'\.RST_N\(RST_N\)', '.RST_N(RST_N_partitionReset)', current_line)
                    print(f"  Patched .RST_N in mkSqGroup at line {j + 1}")
                    modified = True
                    break
                if ');' in current_line and j > i:
                    break
                j += 1
        i += 1

    # Process mkRqGroup
    i = 0
    while i < len(lines):
        line = lines[i]
        if re.search(r'mkRqGroup\s+rqGroup\s*\(', line):
            j = i
            while j < len(lines):
                current_line = lines[j]
                if re.search(r'\.RST_N\(RST_N\)', current_line):
                    lines[j] = re.sub(r'\.RST_N\(RST_N\)', '.RST_N(RST_N_partitionReset)', current_line)
                    print(f"  Patched .RST_N in mkRqGroup at line {j + 1}")
                    modified = True
                    break
                if ');' in current_line and j > i:
                    break
                j += 1
        i += 1

    if modified:
        try:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write('\n'.join(lines))
            print(f"Successfully patched {file_path}")
        except Exception as e:
            print(f"Error writing {file_path}: {e}")
            return False

    return modified


def main():
    parser = argparse.ArgumentParser(
        description='Apply reset signal patch to Verilog files in the specified directory.'
    )
    parser.add_argument(
        'directory',
        type=str,
        help='Relative path to the directory containing the Verilog files'
    )

    args = parser.parse_args()

    # Convert relative path to absolute path
    target_dir = os.path.abspath(args.directory)

    if not os.path.isdir(target_dir):
        print(f"Error: Directory '{target_dir}' does not exist")
        sys.exit(1)

    print(f"Processing directory: {target_dir}")

    # Process mkBsvTop.v
    mkBsvTop_path = find_file(target_dir, 'mkBsvTop.v')
    if mkBsvTop_path:
        print(f"\nFound mkBsvTop.v at: {mkBsvTop_path}")
        patch_mkBsvTop(mkBsvTop_path)
    else:
        print(f"\nWarning: mkBsvTop.v not found in {target_dir}")

    # Process mkQpMrPgtQpc.v
    mkQpMrPgtQpc_path = find_file(target_dir, 'mkQpMrPgtQpc.v')
    if mkQpMrPgtQpc_path:
        print(f"\nFound mkQpMrPgtQpc.v at: {mkQpMrPgtQpc_path}")
        patch_mkQpMrPgtQpc(mkQpMrPgtQpc_path)
    else:
        print(f"\nWarning: mkQpMrPgtQpc.v not found in {target_dir}")

    print("\nDone.")


if __name__ == '__main__':
    main()
