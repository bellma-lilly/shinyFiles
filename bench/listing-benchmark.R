# Benchmark of the server-side listings behind the three dialogs.
#
#   Rscript bench/listing-benchmark.R <label> [root]
#
# Loads shinyFiles from the working tree (pkgload), so run it once before and
# once after a change and compare the files written to bench/results/.
#
# Wall time on NFS depends on the attribute cache, so it is reported for the
# first call (cold-ish) and for repeats. The number that does not depend on the
# cache is the count of filesystem syscalls per call: run under
#   strace -f -e trace=newfstatat,statx,lstat,stat,getdents64,openat -o <file>
# and the markers written to fd 2 delimit each call (see bench/strace-count.sh).

args <- commandArgs(trailingOnly = TRUE)
label <- if (length(args) >= 1) args[[1]] else "run"
root <- if (length(args) >= 2) args[[2]] else as.character(fs::path_home())

suppressMessages(pkgload::load_all(".", quiet = TRUE, export_all = TRUE))

roots <- c(bench = root)
fg <- fileGetter(roots = roots)
dg <- dirGetter(roots = roots)

marker <- function(text) {
  # A write() of a known string, easy to find in an strace log.
  cat(sprintf("@@SF-BENCH %s@@\n", text), file = stderr())
}

calls <- list(
  # What a file chooser / save dialog sends for the root listing.
  file_listing = function() fg(dir = "", root = "bench"),
  # What the folder chooser sends when it opens: root expanded, nothing below.
  dir_tree = function() dg(tree = list(name = "", expanded = TRUE), root = "bench")
)

timings <- lapply(names(calls), function(name) {
  marker(paste("begin", name))
  first <- system.time(calls[[name]]())[["elapsed"]]
  marker(paste("end", name))
  repeats <- vapply(1:3, function(i) system.time(calls[[name]]())[["elapsed"]], numeric(1))
  data.frame(call = name, first_s = first, repeat_median_s = median(repeats))
})
timings <- do.call(rbind, timings)

# Rprof of the tree call, the slow one.
profFile <- file.path("bench", "results", paste0(label, "-dir_tree.Rprof"))
Rprof(profFile, interval = 0.005, line.profiling = TRUE)
invisible(calls$dir_tree())
Rprof(NULL)

top <- length(fs::dir_ls(root, all = FALSE, fail = FALSE))
info <- data.frame(root = root, top_entries = top)

out <- file.path("bench", "results", paste0(label, "-timings.csv"))
write.csv(cbind(timings, info), out, row.names = FALSE)
print(cbind(timings, info))
