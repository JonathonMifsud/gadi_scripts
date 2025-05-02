#!/usr/bin/env python3

from __future__ import annotations
import argparse
import datetime
import time
import sys
from pathlib import Path
from typing import Dict, List, Tuple

def collect_needed_accessions(rvdb_file: Path, quiet=False) -> set[str]:
    needed = set()
    try:
        with rvdb_file.open("r") as f:
            for i, line in enumerate(f, 1):
                if line.startswith('>'):
                    parts = line.strip().split('|')
                    if len(parts) >= 3:
                        needed.add(parts[2])
                if not quiet and i % 1_000_000 == 0:
                    print(f"[INFO] FASTA scanned: {i:,} lines...", file=sys.stderr)
    except Exception as e:
        print(f"[ERROR] Failed reading FASTA: {e}", file=sys.stderr)
        sys.exit(1)
    return needed

def load_filtered_mapping(mapping_file: Path, needed_accs: set[str], quiet=False) -> Dict[str, Tuple[str, str, str]]:
    mapping = {}
    try:
        with mapping_file.open("r") as f:
            for i, line in enumerate(f, 1):
                fields = line.strip().split('\t')
                if len(fields) < 4:
                    continue
                acc, acc_ver, taxid, gi = fields
                if acc_ver in needed_accs:
                    mapping[acc_ver] = (acc, taxid, gi)
                if not quiet and i % 10_000_000 == 0:
                    print(f"[INFO] Mapping lines read: {i:,}", file=sys.stderr)
    except Exception as e:
        print(f"[ERROR] Failed reading mapping file: {e}", file=sys.stderr)
        sys.exit(1)
    return mapping

def map_fasta_headers(rvdb_file: Path, mapping: Dict[str, Tuple[str, str, str]], out_prefix: str, quiet=False):
    mapped_fasta = rvdb_file.with_name(out_prefix + rvdb_file.name)
    month_tag = datetime.datetime.now().strftime("%b-%Y")
    map_table = rvdb_file.parent / f"{out_prefix}accession2taxid.{month_tag}.txt"
    missing = []
    try:
        with rvdb_file.open("r") as fin, mapped_fasta.open("w") as fout, map_table.open("w") as tab:
            tab.write("accession\taccession.version\ttaxid\tgi\n")
            for i, line in enumerate(fin, 1):
                if line.startswith('>'):
                    parts = line.strip().split('|')
                    if len(parts) >= 3:
                        acc_ver = parts[2]
                        if acc_ver in mapping:
                            acc, taxid, gi = mapping[acc_ver]
                            fout.write(f">{acc} {line[1:]}")
                            tab.write(f"{acc}\t{acc_ver}\t{taxid}\t{gi}\n")
                        else:
                            missing.append(parts[0])
                    else:
                        fout.write(line)
                else:
                    fout.write(line)
                if not quiet and i % 1_000_000 == 0:
                    print(f"[INFO] FASTA lines processed: {i:,}", file=sys.stderr)
    except Exception as e:
        print(f"[ERROR] Failed writing outputs: {e}", file=sys.stderr)
        sys.exit(1)
    return mapped_fasta, map_table, missing

def write_missing_ids(missing: List[str], out_prefix: str, output_dir: Path) -> None:
    if not missing:
        return
    path = output_dir / f"{out_prefix}missing_ids.txt"
    try:
        with path.open("w") as f:
            f.write("\n".join(missing))
    except Exception as e:
        print(f"[ERROR] Failed writing missing IDs: {e}", file=sys.stderr)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mapping_file", type=Path)
    parser.add_argument("rvdb_file", type=Path)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    if not args.mapping_file.is_file():
        print(f"[ERROR] Mapping file not found: {args.mapping_file}", file=sys.stderr)
        sys.exit(1)
    if not args.rvdb_file.is_file():
        print(f"[ERROR] FASTA file not found: {args.rvdb_file}", file=sys.stderr)
        sys.exit(1)

    start = time.time()
    print(f"[INFO] Collecting required accession.version entries from FASTA...", file=sys.stderr)
    needed_accs = collect_needed_accessions(args.rvdb_file, args.quiet)

    print(f"[INFO] Loading filtered mapping (~{len(needed_accs):,} targets)...", file=sys.stderr)
    mapping = load_filtered_mapping(args.mapping_file, needed_accs, args.quiet)

    print(f"[INFO] Mapping and writing output...", file=sys.stderr)
    out_prefix = "rvdb."
    renamed_fasta, map_table, missing = map_fasta_headers(args.rvdb_file, mapping, out_prefix, args.quiet)
    write_missing_ids(missing, out_prefix, args.rvdb_file.parent)

    print(f"[INFO] Mapping completed.")
    print(f"[INFO] Renamed FASTA: {renamed_fasta}")
    print(f"[INFO] Mapping table: {map_table}")
    print(f"[INFO] Missing accessions: {len(missing)}")
    print(f"[INFO] Runtime: {time.time() - start:.2f}s")

if __name__ == "__main__":
    main()
