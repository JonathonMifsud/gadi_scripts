#!/usr/bin/env python3

from __future__ import annotations
import argparse
import time
import datetime
from pathlib import Path
from collections import defaultdict
from typing import Dict, List, Tuple
import sys

# Constants
PROT_CHUNK_SIZE = 100_000
RVDB_CHUNK_SIZE = 100_000

# ---------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------

def build_mapping_dict(mapping_path: Path, quiet: bool = False) -> Dict[str, Tuple[str, str, str]]:
    mapping_dict = defaultdict(lambda: ('', '', ''))
    try:
        with mapping_path.open("r") as f:
            for i, line in enumerate(f, 1):
                fields = line.strip().split('\t')
                if len(fields) < 4:
                    if not quiet:
                        print(f"[WARNING] Malformed line {i} in mapping file: {line.strip()}", file=sys.stderr)
                    continue
                acc, acc_version, taxid, gi = fields
                mapping_dict[acc_version] = (acc, taxid, gi)
                if not quiet and i % PROT_CHUNK_SIZE == 0:
                    print(f"[INFO] Processed {i:,} lines of prot.accession2taxid...")
    except FileNotFoundError:
        print(f"[ERROR] Mapping file not found: {mapping_path}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"[ERROR] Failed reading mapping file: {e}", file=sys.stderr)
        sys.exit(1)
    return mapping_dict

def process_rvdb_fasta(mapping_dict: Dict[str, Tuple[str, str, str]],
                       rvdb_path: Path,
                       today: str,
                       quiet: bool = False) -> Tuple[Path, Path, List[str]]:
    renamed_fasta_path = rvdb_path.with_name(rvdb_path.stem + "_renamed" + rvdb_path.suffix)
    mapping_table_path = rvdb_path.parent / f"rvdb.accession2taxid.{today}.txt"
    missing_ids: List[str] = []

    try:
        with rvdb_path.open("r") as fin, \
             renamed_fasta_path.open("w") as fout, \
             mapping_table_path.open("w") as tab:
            tab.write("accession\taccession.version\ttaxid\tgi\n")

            for i, line in enumerate(fin, 1):
                if line.startswith('>'):
                    header = line.strip()[1:]
                    fields = header.split('|')
                    if len(fields) < 3:
                        if not quiet:
                            print(f"[WARNING] Skipping malformed header: {header}", file=sys.stderr)
                        continue
                    p_acc = fields[2]
                    if p_acc in mapping_dict:
                        acc, taxid, gi = mapping_dict[p_acc]
                        fout.write(f">{acc} {header}\n")
                        tab.write(f"{acc}\t{p_acc}\t{taxid}\t{gi}\n")
                    else:
                        missing_ids.append(header)
                else:
                    fout.write(line)

                if not quiet and i % RVDB_CHUNK_SIZE == 0:
                    print(f"[INFO] Processed {i:,} lines of RVDB file...")
    except FileNotFoundError:
        print(f"[ERROR] RVDB FASTA file not found: {rvdb_path}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"[ERROR] Failed while processing RVDB file: {e}", file=sys.stderr)
        sys.exit(1)

    return renamed_fasta_path, mapping_table_path, missing_ids

def write_missing_ids(missing_ids: List[str], today: str, output_dir: Path) -> Path | None:
    if not missing_ids:
        return None
    missing_path = output_dir / f"rvdb_missing_ids.{today}.txt"
    try:
        with missing_path.open("w") as f:
            f.write("\n".join(missing_ids))
    except Exception as e:
        print(f"[ERROR] Failed to write missing IDs: {e}", file=sys.stderr)
        sys.exit(1)
    return missing_path

# ---------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="RVDB Protein Mapping Script (modernized)")
    parser.add_argument("mapping_file", type=Path, help="Path to prot.accession2taxid file")
    parser.add_argument("rvdb_file", type=Path, help="Path to RVDB FASTA file")
    parser.add_argument("--quiet", action="store_true", help="Suppress progress output")
    args = parser.parse_args()

    today = datetime.datetime.now().strftime("%b-%Y")
    start_time = time.time()

    if not args.mapping_file.is_file():
        print(f"[ERROR] Mapping file does not exist: {args.mapping_file}", file=sys.stderr)
        sys.exit(1)

    if not args.rvdb_file.is_file():
        print(f"[ERROR] RVDB FASTA file does not exist: {args.rvdb_file}", file=sys.stderr)
        sys.exit(1)

    if not args.quiet:
        print(f"[INFO] Mapping version: {today}")
        print(f"[INFO] Reading mapping from: {args.mapping_file}")
        print(f"[INFO] Processing FASTA from: {args.rvdb_file}")

    mapping_dict = build_mapping_dict(args.mapping_file, quiet=args.quiet)
    renamed_fasta, mapping_table, missing_ids = process_rvdb_fasta(mapping_dict, args.rvdb_file, today, quiet=args.quiet)
    missing_path = write_missing_ids(missing_ids, today, args.rvdb_file.parent)

    elapsed = time.time() - start_time

    print("\n[INFO] Mapping completed.")
    print(f"[INFO] Renamed FASTA written: {renamed_fasta}")
    print(f"[INFO] Mapping table written: {mapping_table}")
    if missing_path:
        print(f"[INFO] Missing IDs written: {missing_path} ({len(missing_ids)} IDs)")
    print(f"[INFO] Total time: {elapsed:.2f} seconds")

if __name__ == "__main__":
    main()
