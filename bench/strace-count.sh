#!/bin/sh
# Count filesystem syscalls made by each benchmarked call.
#
#   sh bench/strace-count.sh <label> [root]
#   SCRIPT=bench/click-benchmark.R sh bench/strace-count.sh <label> [root]
#
# Writes bench/results/<label>-syscalls.txt.
label=${1:-run}
root=${2:-$HOME}
log=$(mktemp)
strace -f -s 200 -e trace=newfstatat,statx,lstat,stat,getdents64,openat,write -o "$log" \
  Rscript "${SCRIPT:-bench/listing-benchmark.R}" "$label-strace" "$root" > /dev/null 2>&1
out="bench/results/$label-syscalls.txt"
awk '
  /@@SF-BENCH begin/ { match($0, /begin [a-z_0-9]+/); name = substr($0, RSTART + 6, RLENGTH - 6); on = 1; next }
  /@@SF-BENCH end/   { on = 0; next }
  on && /newfstatat|statx|lstat\(|stat\(/ { stat[name]++ }
  on && /getdents64/ { dents[name]++ }
  on && /openat/ { open[name]++ }
  END { printf "%-24s %8s %10s %8s\n", "call", "stat", "getdents", "openat";
        for (n in stat) printf "%-24s %8d %10d %8d\n", n, stat[n], dents[n], open[n] }
' "$log" | tee "$out"
rm -f "$log" bench/results/"$label"-strace-*
