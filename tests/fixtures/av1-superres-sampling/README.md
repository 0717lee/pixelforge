# Superres with independent chroma axes

Real libaom streams at 10-bit, denominator 9, 4:2:2 and 4:4:4. Expected native planes come from dav1d. Regenerate using `python scripts/generate-av1-superres-sampling-reference.py`; `--check` compares in temporary storage without rewriting repository files. Tool paths resolve from PATH or CLI options. The manifest records commands and byte hashes.
