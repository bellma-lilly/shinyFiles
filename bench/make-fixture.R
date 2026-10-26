# Build a fixed-shape tree for the benchmark, on the same NFS mount as the
# repo so attribute lookups cost what they cost for real users.
#
#   Rscript bench/make-fixture.R [dir]
#
# Shape: 400 files + 80 folders at the top; each folder holds 50 files and
# 5 subfolders (so ~4,400 entries one level down -- about the size of the Home
# folder that prompted this).
dir <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[[1]] else "bench/fixture"
if (fs::dir_exists(dir)) fs::dir_delete(dir)
fs::dir_create(dir)
fs::file_create(fs::path(dir, sprintf("file%03d.txt", 1:400)))
for (i in 1:80) {
  sub <- fs::path(dir, sprintf("folder%02d", i))
  fs::dir_create(fs::path(sub, sprintf("child%d", 1:5)))
  fs::file_create(fs::path(sub, sprintf("f%02d.txt", 1:50)))
}
cat("fixture at", as.character(fs::path_real(dir)), "\n")
