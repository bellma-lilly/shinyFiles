# Adversarial tests for typed-path resolution in the shinyFiles path box.
#
# The pencil button opens a text field so a user can type a location instead of
# clicking to it. The bug these pin: `setPathFromTextInput` tried to detect a
# volume with `path.startsWith($(volume).val())`, but a volume option's value is
# its *name* ("Home"), never its filesystem path. That never matches a real
# path, so typed text always fell through to the relative branch and was
# appended under the selected root — `/lrlhps/users/me/proj` became
# `<root>/lrlhps/users/me/proj` and the dialog reported "Folder does not exist".
#
# The client only knows root names, so it cannot tell which root an absolute
# path belongs to. Resolution has to happen server-side.
#
# Contract under test: `resolveTypedPath(roots, text, currentRoot)` returns
# `list(root = <name>, path = <character vector of segments>)` for a location
# inside some root, or NULL when the text resolves outside every root.

tree <- local({
  base <- fs::path(tempfile("sf-typed"))
  fs::dir_create(fs::path(base, "documents", "archive"))
  fs::dir_create(fs::path(base, "images"))
  fs::file_create(fs::path(base, "readme.txt"))
  fs::path_real(base)
})

roots <- c(
  test_data = as.character(tree),
  docs = as.character(fs::path(tree, "documents"))
)

expect_resolves <- function(text, currentRoot, root, path) {
  res <- resolveTypedPath(roots, text, currentRoot)
  expect_equal(res$root, root)
  expect_equal(as.character(res$path), path)
}

# === Absolute paths: the actual reported bug ===

test_that("an absolute path to the root itself resolves to the root", {
  expect_resolves(as.character(tree), "test_data", "test_data", character(0))
})

test_that("an absolute path inside the current root is not appended onto it", {
  expect_resolves(
    as.character(fs::path(tree, "documents", "archive")),
    "test_data",
    "test_data",
    c("documents", "archive")
  )
})

test_that("an absolute path reachable only from another root switches root", {
  expect_resolves(
    as.character(fs::path(tree, "images")), "docs", "test_data", "images"
  )
})

test_that("the current root wins when several roots contain the path", {
  typed <- as.character(fs::path(tree, "documents", "archive"))

  expect_resolves(typed, "test_data", "test_data", c("documents", "archive"))
  expect_resolves(typed, "docs", "docs", "archive")
})

test_that("the longest matching root wins when the current root does not match", {
  many <- c(
    docs = as.character(fs::path(tree, "documents")),
    images = as.character(fs::path(tree, "images")),
    everything = as.character(tree)
  )
  res <- resolveTypedPath(many, as.character(fs::path(tree, "documents", "archive")), "images")

  expect_equal(res$root, "docs")
  expect_equal(as.character(res$path), "archive")
})

# === Escaping the roots ===

test_that("an absolute path outside every root is rejected", {
  expect_null(resolveTypedPath(roots, "/etc", "test_data"))
})

test_that("the filesystem root is rejected when no root is the filesystem root", {
  expect_null(resolveTypedPath(roots, "/", "test_data"))
})

test_that("a dotdot escape in an absolute path is rejected", {
  expect_null(resolveTypedPath(roots, paste0(tree, "/../.."), "test_data"))
})

test_that("a dotdot escape in a relative path is rejected", {
  expect_null(resolveTypedPath(roots, "../..", "test_data"))
})

test_that("dotdot that stays inside the root is normalized away", {
  expect_resolves(
    as.character(fs::path(tree, "documents", "..", "images")),
    "test_data",
    "test_data",
    "images"
  )
})

test_that("a sibling root sharing a name prefix is rejected", {
  base <- fs::path(tempfile("sf-prefix"))
  fs::dir_create(fs::path(base, "data"))
  fs::dir_create(fs::path(base, "data2"))
  base <- fs::path_real(base)
  prefixed <- c(data = as.character(fs::path(base, "data")))

  expect_null(resolveTypedPath(prefixed, as.character(fs::path(base, "data2")), "data"))
})

test_that("a symlink pointing outside the root is rejected", {
  skip_on_os("windows")
  link <- fs::path(tree, "escape-link")
  if (!fs::link_exists(link)) fs::link_create("/etc", link)
  on.exit(unlink(as.character(link)), add = TRUE)

  expect_null(resolveTypedPath(roots, as.character(link), "test_data"))
})

# === Relative paths stay root-relative ===

test_that("a relative path resolves within the current root", {
  expect_resolves(
    "documents/archive", "test_data", "test_data", c("documents", "archive")
  )
})

test_that("a relative path respects the selected root", {
  expect_resolves("archive", "docs", "docs", "archive")
})

test_that("a relative path never nests a list inside the segments", {
  # The upstream relative branch did `data.path.push(path.split(...))`, pushing
  # an array as a single element. Collapsing that yields 'list("archive")'.
  res <- resolveTypedPath(roots, "documents/archive", "test_data")

  expect_type(res$path, "character")
  expect_false(any(grepl("list(", as.character(res$path), fixed = TRUE)))
})

# === Normalization of sloppy input ===

test_that("a trailing slash does not create an empty segment", {
  expect_resolves(
    paste0(fs::path(tree, "documents"), "/"), "test_data", "test_data", "documents"
  )
})

test_that("repeated separators are collapsed", {
  expect_resolves(
    paste0(tree, "//documents"), "test_data", "test_data", "documents"
  )
})

test_that("surrounding whitespace is ignored", {
  expect_resolves(
    paste0("  ", fs::path(tree, "documents"), "  "),
    "test_data",
    "test_data",
    "documents"
  )
})

test_that("empty and whitespace-only text resolve to the root", {
  expect_resolves("", "test_data", "test_data", character(0))
  expect_resolves("   ", "test_data", "test_data", character(0))
})

test_that("a backslash-separated path is split into segments", {
  # fs normalizes backslashes to the platform separator on both POSIX and
  # Windows, so a user pasting a Windows-style relative path gets segments
  # rather than one directory with a backslash in its name.
  expect_resolves(
    "documents\\archive", "test_data", "test_data", c("documents", "archive")
  )
})

test_that("tilde is never left as a literal path segment", {
  res <- resolveTypedPath(roots, "~", "test_data")

  expect_true(is.null(res) || !("~" %in% as.character(res$path)))
})

# === Hostile and malformed input ===

test_that("an unknown current root falls back instead of erroring", {
  expect_resolves(
    as.character(fs::path(tree, "images")), "nope", "test_data", "images"
  )
})

test_that("a NULL current root falls back instead of erroring", {
  res <- resolveTypedPath(roots, as.character(fs::path(tree, "images")), NULL)

  expect_equal(res$root, "test_data")
  expect_equal(as.character(res$path), "images")
})

test_that("non-character text is rejected without erroring", {
  for (bad in list(NULL, NA, 42L, list(), character(0))) {
    expect_null(resolveTypedPath(roots, bad, "test_data"))
  }
})

test_that("a multi-element character vector is rejected without erroring", {
  expect_null(resolveTypedPath(roots, c("documents", "images"), "test_data"))
})

test_that("absurdly long text is rejected without erroring", {
  expect_null(resolveTypedPath(roots, strrep("a/", 5000), "test_data"))
})

test_that("unnamed roots error, as the rest of the package does", {
  expect_error(resolveTypedPath(c("/tmp"), "documents", "test_data"))
})

test_that("roots given as a function are supported", {
  fnRoots <- function() roots
  res <- resolveTypedPath(fnRoots, as.character(fs::path(tree, "images")), "test_data")

  expect_equal(res$root, "test_data")
  expect_equal(as.character(res$path), "images")
})

test_that("a root configured with a trailing slash still matches", {
  slashed <- c(test_data = paste0(tree, "/"))
  res <- resolveTypedPath(slashed, as.character(fs::path(tree, "images")), "test_data")

  expect_equal(res$root, "test_data")
  expect_equal(as.character(res$path), "images")
})

# === fileGetter clamps escapes rather than leaking ===
#
# fileGetter already handles a traversing path by falling back to the root and
# clearing the breadcrumbs. These pin that, so a typed-path fix routed through
# the getter cannot quietly start serving content from outside the root.

test_that("fileGetter clamps an escaping path back to its root", {
  listing <- fileGetter(roots)(paste0(c("..", ".."), collapse = "/"), "test_data")
  atRoot <- fileGetter(roots)("", "test_data")

  expect_true(listing$exist)
  expect_equal(as.character(listing$breadcrumps), "")
  expect_equal(listing$files$filename, atRoot$files$filename)
})

test_that("fileGetter never serves content from outside the root", {
  listing <- fileGetter(roots)("../../etc", "test_data")
  atRoot <- fileGetter(roots)("", "test_data")

  expect_equal(listing$files$filename, atRoot$files$filename)
  expect_equal(listing$root, "test_data")
  expect_equal(as.character(listing$roots), c("test_data", "docs"))
})

test_that("a typed file path is not reported as an existing directory", {
  res <- resolveTypedPath(roots, as.character(fs::path(tree, "readme.txt")), "test_data")

  if (!is.null(res)) {
    listing <- fileGetter(roots)(paste0(res$path, collapse = "/"), res$root)
    # fileGetter deliberately backs up to the containing directory and names the
    # file in selectedFile — what it must never do is list the file as a dir.
    expect_equal(as.character(listing$selectedFile), "readme.txt")
  }
})
