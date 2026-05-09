#!/usr/bin/env python3

import os
import sys

in_fofn=sys.argv[1]
fn_stub=sys.argv[2]
out_fofn=sys.argv[3]
ds = {}

for i in open(in_fofn):
     line = i.rstrip()
     sl = line.split(fn_stub)
     lsl=len(sl)
     if len(sl) > 1:
         k=float(sl[1].split('.')[0].split('-')[0].replace('~','.'))
         chrm=int(str(k).split('.')[0])
         if int(chrm) not in ds.keys():
             ds[int(chrm)] = {}
         ds[chrm][int(str(k).split('.')[1])] = line
     else:
          os.system(f'echo "EeRROROROROROROROROR:     This line failing to parse:{line}" 2> ')
          os._exit(22)

for ix in sorted(ds):
     for ixx in sorted(ds[ix]):
         os.system(f"echo {ds[ix][ixx]} >> {out_fofn}")

os._exit(0)
