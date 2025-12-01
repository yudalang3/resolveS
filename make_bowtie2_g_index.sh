#!/bin/bash

# Download or move the db
# cp /opt/BioInfo/database/rRNAdb/smr_v4.3_default_db.fasta db
rm ref_bowtie2/default*
# Convert to DNA
# sed 's/U/T/g; s/u/t/g' is equivalent to sed 'y/Uu/Tt/', but faster
sed 'y/Uu/Tt/' db/smr_v4.3_default_db.fasta > db/smr_v4.3_default_db_dna.fasta
bowtie2-build --threads 20 db/smr_v4.3_default_db_dna.fasta ref_bowtie2/default
