#!/usr/bin/env python3
"""
Scanner to verify that NO em dashes (U+2014) or en dashes (U+2013) exist
in any file in the repository.
"""

import os
import sys

FORBIDDEN_CHARS = {
    '\u2014': 'EM DASH (U+2014)',
    '\u2013': 'EN DASH (U+2013)',
}

def scan_file(filepath):
    violations = []
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            for line_no, line in enumerate(f, start=1):
                for char, name in FORBIDDEN_CHARS.items():
                    if char in line:
                        col = line.index(char) + 1
                        violations.append((line_no, col, name, line.strip()))
    except Exception as e:
        # Ignore binary files or unreadable files
        pass
    return violations

def main():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    has_violations = False
    checked_files = 0

    ignore_dirs = {'.git', '.system_generated', '__pycache__', 'build', '.cache'}

    for dirpath, dirnames, filenames in os.walk(root_dir):
        dirnames[:] = [d for d in dirnames if d not in ignore_dirs]
        for filename in filenames:
            if filename.endswith(('.png', '.jpg', '.so', '.dylib', '.a', '.o', '.out')):
                continue
            filepath = os.path.join(dirpath, filename)
            relpath = os.path.relpath(filepath, root_dir)
            violations = scan_file(filepath)
            checked_files += 1
            if violations:
                has_violations = True
                print(f"[FAIL] Forbidden dash found in {relpath}:")
                for line_no, col, name, line_content in violations:
                    print(f"  Line {line_no}, Col {col}: {name}")
                    print(f"    {line_content}")

    if has_violations:
        print(f"\nScan failed. One or more em/en dashes detected.")
        sys.exit(1)
    else:
        print(f"[PASS] Scanned {checked_files} files. Zero em/en dashes found.")
        sys.exit(0)

if __name__ == '__main__':
    main()
