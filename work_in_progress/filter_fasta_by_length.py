import sys

def filter_fasta_by_length(input_fasta, output_fasta, min_length=None, max_length=None):
    """
    Filter sequences in a FASTA file by sequence length in a memory-efficient manner.
    """
    min_length = int(min_length) if min_length != "None" else None
    max_length = int(max_length) if max_length != "None" else None

    with open(input_fasta, "r") as infile, open(output_fasta, "w") as outfile:
        current_header = None
        current_sequence = []

        for line in infile:
            if line.startswith(">"):
                # If there's a sequence being processed, check its length and write it out if it meets the criteria
                if current_header and current_sequence:
                    sequence = ''.join(current_sequence)
                    sequence_length = len(sequence)
                    if (min_length is None or sequence_length >= min_length) and \
                       (max_length is None or sequence_length <= max_length):
                        outfile.write(current_header)
                        outfile.write(sequence + "\n")
                
                # Start a new sequence
                current_header = line
                current_sequence = []
            else:
                current_sequence.append(line.strip())

        # Process the last sequence in the file
        if current_header and current_sequence:
            sequence = ''.join(current_sequence)
            sequence_length = len(sequence)
            if (min_length is None or sequence_length >= min_length) and \
               (max_length is None or sequence_length <= max_length):
                outfile.write(current_header)
                outfile.write(sequence + "\n")

if __name__ == "__main__":
    input_fasta = sys.argv[1]
    output_fasta = sys.argv[2]
    min_length = sys.argv[3]
    max_length = sys.argv[4]
    filter_fasta_by_length(input_fasta, output_fasta, min_length, max_length)
