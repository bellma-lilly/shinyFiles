## Submission

This is an update of shinyFiles from 0.9.3 (published on CRAN) to 0.9.4, and is
accompanied by a **maintainer change**. Thomas Lin Pedersen
(thomasp85@gmail.com), the previous maintainer, has agreed in writing to hand
maintenance of the package to Michael Bell (bell_michael_a@lilly.com). Thomas
will confirm the transfer separately from his own address to
CRAN-submissions@R-project.org. Thomas remains an author of the package.

The release ships accumulated feature and fix work since 0.9.3: a "Recent"
folders group in the volume dropdown, typed-path resolution against the
configured roots, a loading overlay during directory listings, a substantial
performance rework of the folder chooser on networked filesystems, reactive
`...` arguments in `shinyFileSave()`, and a fix for keyboard/backdrop handling
with multiple shinyFiles dialogs open at once. See NEWS.md for the full list.

No exported function or argument has been removed.

## R CMD check results

0 errors | 0 warnings | 2 notes

* New maintainer: expected, this submission is the maintainer-change itself
  (see above); Thomas Lin Pedersen is confirming separately.
* "unable to verify current time": the local check host has no outbound
  time-service access; not expected on CRAN's own check machines.

(`R CMD check --as-cran` also flagged the `shinyFiles/shinyFiles` GitHub URLs
in DESCRIPTION/man as unreachable; this is expected until the repository
transfer below completes, at which point they resolve.)

## Test environments

* local: Red Hat Enterprise Linux 9.8, R 4.5.2
* GitHub Actions: ubuntu-latest (R-devel, R-release, R-oldrel-1 to -4),
  windows-latest (R-release, R 3.6), macOS-latest (R-release)

## Reverse dependencies

We checked all 56 reverse dependencies on CRAN (36 that depend on or import
shinyFiles, plus 20 that suggest it), running R CMD check on each package's
source against shinyFiles 0.9.3 from CRAN and against 0.9.4.

* We saw 0 new problems.
* We failed to check 0 packages.

9 packages (AbSolution, aifeducation, blockr.io, DQAgui, dqcheckrGUI, Eagle,
pmxcode, Racmacs, shinyMixR) have one ERROR that occurs identically with 0.9.3
and 0.9.4: failing tests or vignettes unrelated to shinyFiles, or compiled
dependencies (RcppArmadillo, RcppEigen) that were unavailable on the check
machine.
