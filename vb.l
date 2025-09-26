VerifyBamID2: A robust tool for DNA contamination estimation from sequence reads using ancestry-agnostic method.

 Version:2.0.1
 Copyright (c) 2009-2020 by Hyun Min Kang and Fan Zhang
 This project is licensed under the terms of the MIT license.

Detailed instructions of parameters are availanle. Ones with "[]" are in effect:

Input/Output Files - Input/Output files for the program[Complete Path Recommended]
  --BamFile            [STR: Empty]        : [String] Bam or Cram file for the sample[Required if --PileupFile not specified]
  --PileupFile         [STR: Empty]        : [String] Pileup file for the sample[Required if --BamFile not specified]
  --Reference          [STR: Empty]        : [String] Reference file[Required]
  --SVDPrefix          [STR: Empty]        : [String] SVD related files prefix(normally shared by .UD, .mu and .bed files)[Required]
  --Output             [STR: result]       : [String] Prefix of output files[optional]

Model Selection Options - Options to adjust model selection and parameters
  --WithinAncestry     [FLG: OFF]          : [Bool] Enabling withinAncestry assume target sample and contamination source are from the same populations,[default:BetweenAncestry] otherwise
  --DisableSanityCheck [FLG: OFF]          : [Bool] Disable marker quality sanity check(no marker filtering)[default:false]
  --NumPC              [INT: 2]            : [Int] Set number of PCs to infer Allele Frequency[optional]
  --FixPC              [STR: Empty]        : [String] Input fixed PCs to estimate Alpha[format PC1:PC2:PC3...]
  --FixAlpha           [FLT: -1.0e+00]     : [Double] Input fixed Alpha to estimate PC coordinates
  --KnownAF            [STR: Empty]        : [String] known allele frequency file (chr	pos	freq)[Optional]
  --NumThread          [INT: 4]            : [Int] Set number of threads in likelihood calculation[default:4]
  --Seed               [INT: 12345]        : [Int] Random number seed[default:12345]
  --Epsilon            [FLT: 1.0e-08]      : [Double] Minimization procedure convergence threshold, usually a trade-off bettween accuracy and running time[default:1e-10]
  --OutputPileup       [FLG: OFF]          : [Bool] If output temp pileup file
  --Verbose            [FLG: OFF]          : [Bool] If print the progress of the method on the screen

Construction of SVD Auxiliary Files - Use these options when generating SVDPrefix files
  --RefVCF             [STR: Empty]        : [String] VCF file from which to extract reference panel's genotype matrix[Required if no SVD files available]

Pileup Options - Arguments for pileup info extraction
  --min-BQ             [INT: 13]           : [Int] skip bases with baseQ/BAQ smaller than min-BQ
  --min-MQ             [INT: 2]            : [Int] skip alignments with mapQ smaller than min-MQ
  --adjust-MQ          [INT: 40]           : [Int] adjust mapping quality; recommended:50, disable:0
  --max-depth          [INT: 8000]         : [Int] max per-file depth
  --no-orphans         [FLG: OFF]          : [Bool] do not use anomalous read pairs
  --incl-flags         [INT: 1040]         : [Int] required flags: skip reads with mask bits unset
  --excl-flags         [INT: 1796]         : [Int] filter flags: skip reads with mask bits set

Deprecated Options - These options still are available but not recommended
  --UDPath             [STR: Empty]        : [String] UD matrix file from SVD result of genotype matrix
  --MeanPath           [STR: Empty]        : [String] Mean matrix file of genotype matrix
  --BedPath            [STR: Empty]        : [String] Bed file for markers used in this analysis,1 based pos(chr	pos-1	pos	refAllele	altAllele)[Required]


NOTES:
When --help was included in the argument. The program prints the help message but do not actually run
a
