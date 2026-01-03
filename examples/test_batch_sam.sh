#!/bin/bash
# Test resolveS batch mode with SAM files
# Uses -b option with 1-column metadata file (auto-detected as SAM batch)

../bin/resolveS -b data/batch_sam_metadata.txt
