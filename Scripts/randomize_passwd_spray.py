#use for password spraying on randomize the email while spraying
import random

# Input and output filenames
input_file = "input.txt"
output_file = "output.txt"

# Read all lines from the input file
with open(input_file, "r", encoding="utf-8") as f:
    lines = f.readlines()

# Remove any trailing newlines/spaces
lines = [line.strip() for line in lines if line.strip()]

# Shuffle the lines randomly
random.shuffle(lines)

# Write the randomized lines back to a new file
with open(output_file, "w", encoding="utf-8") as f:
    for line in lines:
        f.write(line + "\n")

print(f"✅ Randomized lines saved to '{output_file}'")
