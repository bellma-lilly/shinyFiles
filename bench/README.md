# Listing benchmarks

Scripts for measuring the server-side listings behind the dialogs.

- `make-fixture.R`: builds `bench/fixture/`, a fixed-shape tree on the repo's
  NFS mount: 400 files and 80 folders at the top, each folder holding 50 files
  and 5 subfolders.
- `listing-benchmark.R <label> [root]`: wall time for the flat listing (file
  chooser and save dialog) and the folder tree (folder chooser), plus an Rprof
  of the tree. Writes to `results/`.
- `strace-count.sh <label> [root]`: filesystem syscalls per call. This number
  doesn't depend on the NFS attribute cache, so it's the one to compare.

## 2026-10-26: tree no longer lists collapsed folders; folders found from entry types

Fixture (480 entries at the top, ~4,400 one level down):

| call         | stat before | stat after | getdents before | getdents after |
|--------------|------------:|-----------:|----------------:|---------------:|
| dir_tree     | 4,961       | 81         | 243             | 3              |
| file_listing | 963         | 483        | 3               | 3              |

Home (490 entries, 82 folders, 3,947 entries one level down):

| call         | stat before | stat after | first-call before | first-call after |
|--------------|------------:|-----------:|------------------:|-----------------:|
| dir_tree     | 8,310       | 572        | 0.88 s            | 0.06 s           |
| file_listing | 1,462       | 982        | 0.10 s            | 0.19 s           |

Wall times depend on the cache, so the earlier cold measurement of the tree on
Home was 4.66 s. The file_listing first-call times are noise from the cache
being warmed by the previous run. Raw output is in `results/baseline-*` and
`results/after-*`.

## 2026-10-26: folder chooser keeps listings for as long as the dialog is open

`click-benchmark.R` plays a sequence of clicks in an open folder chooser on the
fixture: three folders expanded, two highlighted, one collapsed. Filesystem
syscalls per click (`SCRIPT=bench/click-benchmark.R sh bench/strace-count.sh`):

| click                  | stat before | stat after | getdents before | getdents after |
|------------------------|------------:|-----------:|----------------:|---------------:|
| open                   | 81          | 81         | 3               | 3              |
| expand_folder01        | 88          | 7          | 6               | 3              |
| expand_folder02        | 94          | 7          | 9               | 3              |
| expand_folder01_child1 | 95          | 2          | 11              | 2              |
| highlight_folder03     | 153         | 59         | 14              | 3              |
| expand_folder03        | 159         | 7          | 17              | 3              |
| highlight_folder01     | 159         | 59         | 17              | 3              |
| collapse_folder02      | 153         | 1          | 14              | 0              |

Before, each click's cost grew with the number of expanded folders, because
the whole tree was re-read every time. After, a click only reads the folder it
touches. A highlight still costs ~59 lookups because the content pane needs
size and date info for that folder's entries. Raw output is in
`results/baseline-clicks-*` and `results/after-clicks-*`.
