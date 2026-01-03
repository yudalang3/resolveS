#!/bin/bash
# Test resolveS with pre-aligned SAM file using -a option
# This test skips the alignment step and directly analyzes the SAM file

../bin/resolveS -a data/test1.sam
