#!/usr/bin/env python3

import os
import re
import time
import argparse
import sys
import torch
from transformers import T5Tokenizer, AutoModelForSeq2SeqLM

def read_fasta(file_path):
    sequences = {}
    with open(file_path, 'r') as f:
        current_id = None
        current_seq = []
        for line in f:
            line = line.strip()
            if line.startswith('>'):
                if current_id is not None:
                    sequences[current_id] = ''.join(current_seq)
                current_id = line[1:]
                current_seq = []
            else:
                current_seq.append(line)
        if current_id is not None:
            sequences[current_id] = ''.join(current_seq)
    return sequences

def write_fasta(file_path, sequences):
    with open(file_path, 'w') as f:
        for seq_id, prediction in sequences.items():
            f.write(f">{seq_id}\n{prediction}\n")

def split_into_chunks(seq, chunk_size):
    return [seq[i:i+chunk_size] for i in range(0, len(seq), chunk_size)]

def main(args):
    # Fix OpenMP conflicts (important for Gadi)
    os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

    device = torch.device(args.device if torch.cuda.is_available() or args.device == "cpu" else "cpu")
    print(f"[INFO] Using device: {device}")

    # Step 1: Read input FASTA
    print(f"[INFO] Reading input FASTA: {args.input}")
    sequences = read_fasta(args.input)
    print(f"[INFO] Loaded {len(sequences)} sequences.")

    # Step 2: Load ProstT5 model from local path
    model_dir = "/g/data/fo27/models/prostT5/"
    print(f"[INFO] Loading ProstT5 model from {model_dir}...")
    try:
        tokenizer = T5Tokenizer.from_pretrained(model_dir, do_lower_case=False)
        model = AutoModelForSeq2SeqLM.from_pretrained(model_dir).to(device)
        model = model.float()
    except Exception as e:
        print(f"[ERROR] Failed to load ProstT5 model: {e}")
        sys.exit(1)
    print("[INFO] Model loaded successfully.")

    # Step 3: Process sequences
    processed_sequences = {}
    start_time = time.time()

    for idx, (seq_id, seq) in enumerate(sequences.items(), start=1):
        try:
            print(f"\n[SEQ {idx}/{len(sequences)}] Processing: {seq_id}")

            clean_seq = re.sub(r"[UZOB]", "X", seq.upper())
            prediction = ""

            if args.chunk_threshold > 0 and len(clean_seq) > args.chunk_threshold:
                print(f"[SEQ {idx}] ⚠️ Sequence longer than {args.chunk_threshold} residues — splitting into chunks...")
                chunks = split_into_chunks(clean_seq, args.chunk_threshold)
                stitched = ""

                for ci, chunk in enumerate(chunks):
                    print(f"[SEQ {idx}]   Chunk {ci+1}/{len(chunks)} (len={len(chunk)})")
                    model_input = "<AA2fold> " + " ".join(list(chunk))
                    inputs = tokenizer(model_input, return_tensors="pt").to(device)

                    with torch.no_grad():
                        output_ids = model.generate(
                            inputs.input_ids,
                            attention_mask=inputs.attention_mask,
                            do_sample=False,
                            min_length=len(chunk),
                            max_length=len(chunk) + 10
                        )

                    sub_prediction = tokenizer.decode(output_ids[0], skip_special_tokens=True).replace(" ", "")
                    stitched += sub_prediction

                prediction = stitched
                print(f"[SEQ {idx}] Chunked prediction complete. Final stitched length: {len(prediction)}")
                print(f"[WARN] ⚠️ {seq_id} exceeded {args.chunk_threshold} residues and was chunk-processed. Accuracy may be affected.")

            else:
                model_input = "<AA2fold> " + " ".join(list(clean_seq))
                inputs = tokenizer(model_input, return_tensors="pt").to(device)

                with torch.no_grad():
                    output_ids = model.generate(
                        inputs.input_ids,
                        attention_mask=inputs.attention_mask,
                        do_sample=False,
                        min_length=len(clean_seq),
                        max_length=len(clean_seq) + 10
                    )

                prediction = tokenizer.decode(output_ids[0], skip_special_tokens=True).replace(" ", "")
                print(f"[SEQ {idx}] Prediction complete. Output length: {len(prediction)}")

            processed_sequences[seq_id] = prediction

        except Exception as e:
            print(f"[ERROR] Failed to process {seq_id}: {e}")
            processed_sequences[seq_id] = "ERROR"

        if idx % args.progress_every == 0 or idx == len(sequences):
            elapsed = time.time() - start_time
            print(f"[INFO] Progress: {idx}/{len(sequences)} ({(idx/len(sequences))*100:.2f}%). Elapsed: {elapsed:.1f}s")
            sys.stdout.flush()

    # Step 4: Write output FASTA
    print(f"\n[INFO] Writing output to: {args.output}")
    write_fasta(args.output, processed_sequences)

    total_time = time.time() - start_time
    print(f"✅ Done! Predictions saved to: {args.output}")
    print(f"[INFO] Total elapsed time: {total_time/60:.2f} minutes")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run ProstT5 AA2fold prediction on a FASTA file.")
    parser.add_argument("-i", "--input", required=True, help="Input FASTA file")
    parser.add_argument("-o", "--output", required=True, help="Output FASTA file")
    parser.add_argument("--device", default="cpu", choices=["cpu", "cuda"], help="Device to run on (cpu or cuda)")
    parser.add_argument("--progress-every", type=int, default=10, help="Progress report interval (in sequences)")
    parser.add_argument("--chunk-threshold", type=int, default=500, help="Max sequence length before chunking is triggered. Use 0 to disable chunking.")
    args = parser.parse_args()
    main(args)
