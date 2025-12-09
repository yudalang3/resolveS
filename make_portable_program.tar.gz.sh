#!/bin/bash

rm db/portable_program_v0.0.4.tar.gz
tar zcvf db/portable_program_v0.0.4.tar.gz --exclude='ref_bowtie2/bowtie2' ref_bowtie2/ align_by_bowtie2.sh benchmark/ check_strand.py count_sam.sh LICENSE resolveS README*


