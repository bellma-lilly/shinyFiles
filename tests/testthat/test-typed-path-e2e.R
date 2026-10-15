# End-to-end tests for typed-path navigation, driven through a real browser.
#
# These complement test-typed-path.R, which unit-tests resolveTypedPath(). What
# they add is the wiring: the path box lives behind the pencil (textChoice)
# dropdown, and its text has to reach the server as `typed` and come back as a
# listing. A resolver that works in isolation but is not plumbed through would
# pass the unit tests and fail these.
#
# The pencil dropdown is the part worth driving for real: it is hidden until
# clicked, its input only submits on keyup with keyCode 13, and the directory
# chooser needs the server-built tree to render the destination.

library(shinytest2)

# Browser-driven, so skipped where no browser or shinytest2 is available.
skipUnlessBrowser <- function() {
  skip_if_not_installed("shinytest2")
  skip_if_not_installed("chromote")
  skip_on_cran()
}

# Mirrors the root layout that exposed the bug: the default root
# does not contain the tree an absolute path points into, so typing one used to
# resolve under <root>/abs/path and report "Folder does not exist".
appDir <- local({
  dir <- fs::path(tempfile("sf-e2e"))
  fs::dir_create(fs::path(dir, "data", "documents", "archive"))
  fs::dir_create(fs::path(dir, "data", "images"))
  fs::file_create(fs::path(dir, "data", "readme.txt"))
  fs::file_create(fs::path(dir, "data", "documents", "notes.txt"))
  fs::dir_create(fs::path(dir, "elsewhere", "target"))

  writeLines(
    c(
      'library(shiny)',
      'library(shinyFiles)',
      'base <- Sys.getenv("SF_E2E_BASE")',
      'roots <- c(',
      '  docs = file.path(base, "data", "documents"),',
      '  data = file.path(base, "data"),',
      '  elsewhere = file.path(base, "elsewhere")',
      ')',
      'ui <- fluidPage(',
      '  shinyDirButton("dir", "Pick dir", "Pick a directory"),',
      '  verbatimTextOutput("dirpath"),',
      '  shinyFilesButton("file", "Pick file", "Pick a file", multiple = FALSE),',
      '  verbatimTextOutput("filepath")',
      ')',
      'server <- function(input, output, session) {',
      '  shinyDirChoose(input, "dir", roots = roots)',
      '  shinyFileChoose(input, "file", roots = roots)',
      '  output$dirpath <- renderText({',
      '    req(input$dir)',
      '    as.character(parseDirPath(roots, input$dir))',
      '  })',
      '  output$filepath <- renderText({',
      '    req(input$file)',
      '    fi <- parseFilePaths(roots, input$file)',
      '    if (nrow(fi) == 0) "" else as.character(fi$datapath[[1]])',
      '  })',
      '}',
      'shinyApp(ui, server)'
    ),
    fs::path(dir, "app.R")
  )
  as.character(fs::path_real(dir))
})

base <- appDir

withr::local_envvar(c(SF_E2E_BASE = base), .local_envir = teardown_env())

# --- helpers ----------------------------------------------------------------

# The pencil dropdown is hidden until clicked, and its input submits on a
# keyup with keyCode 13 -- set_inputs() cannot reach it, so go through the DOM.
typeIntoPathBox <- function(app, text) {
  app$run_js(sprintf("
    var modal = $('.sF-modalContainer:visible').last();
    modal.find('.sF-textChoice').trigger('click');
    var input = modal.find('.sF-textChoice input');
    input.val(%s);
    var e = $.Event('keyup');
    e.keyCode = 13;
    input.trigger(e);
  ", jsonlite::toJSON(text, auto_unbox = TRUE)))
  app$wait_for_idle()
}

openChooser <- function(app, id) {
  app$click(id)
  app$wait_for_idle()
}

visibleDirNames <- function(app) {
  app$get_js("
    $('.sF-modalContainer:visible').last()
      .find('.sF-dirList .sF-file-name').map(function(){
        return $(this).text().trim();
      }).toArray().join(',')
  ")
}

selectedRootOf <- function(app) {
  # The dialog keeps its resolved root in the modal's currentData, which is
  # what the server last sent back -- not in the breadcrumb markup.
  app$get_js("
    ($('.sF-modalContainer:visible').last().data('currentData') || {}).selectedRoot
      || ($('.sF-modalContainer:visible').last().data('currentData') || {}).root
      || null
  ")
}

clickSelect <- function(app) {
  app$run_js(
    "$('.sF-modalContainer:visible').last().find('#sF-selectButton').trigger('click')"
  )
  app$wait_for_idle()
}

warningShown <- function(app) {
  app$get_js("$('.sF-modalContainer:visible').last().find('.sF-warning').length > 0")
}

# --- directory chooser ------------------------------------------------------

test_that("an absolute path typed into the dir chooser resolves and switches root", {
  skipUnlessBrowser()
  app <- AppDriver$new(appDir, name = "dir-typed-abs", load_timeout = 30000)
  on.exit(app$stop(), add = TRUE)

  openChooser(app, "dir")
  # Default root is `docs`, which does not contain the elsewhere/ tree -- the
  # exact condition that used to produce "Folder does not exist".
  expect_equal(selectedRootOf(app), "docs")

  typeIntoPathBox(app, fs::path(base, "elsewhere", "target"))

  expect_equal(selectedRootOf(app), "elsewhere")
  expect_false(warningShown(app))
})

test_that("a typed dir path is returned by parseDirPath", {
  skipUnlessBrowser()
  app <- AppDriver$new(appDir, name = "dir-typed-parse", load_timeout = 30000)
  on.exit(app$stop(), add = TRUE)

  openChooser(app, "dir")
  typeIntoPathBox(app, fs::path(base, "data", "documents", "archive"))

  clickSelect(app)

  expect_equal(
    app$get_value(output = "dirpath"),
    as.character(fs::path(base, "data", "documents", "archive"))
  )
})

test_that("the dir chooser expands the tree along a typed path", {
  skipUnlessBrowser()
  # The tree renders a node only when its parent chain is flagged expanded.
  # This is the assertion that fails if expandedTreeAlong() is not applied.
  app <- AppDriver$new(appDir, name = "dir-typed-tree", load_timeout = 30000)
  on.exit(app$stop(), add = TRUE)

  openChooser(app, "dir")
  typeIntoPathBox(app, fs::path(base, "data", "documents", "archive"))

  # The default root `docs` is data/documents, which already contains this
  # path, so the selected root is kept -- the listing is identical either way.
  expect_equal(selectedRootOf(app), "docs")
  expect_match(visibleDirNames(app), "archive")
})

test_that("a dir path outside every root does not navigate", {
  skipUnlessBrowser()
  app <- AppDriver$new(appDir, name = "dir-typed-escape", load_timeout = 30000)
  on.exit(app$stop(), add = TRUE)

  openChooser(app, "dir")
  typeIntoPathBox(app, "/etc")

  expect_true(warningShown(app))
  expect_false(grepl("passwd", visibleDirNames(app), fixed = TRUE))

  # The observer is still alive: a real path still works afterwards.
  typeIntoPathBox(app, fs::path(base, "data", "images"))
  expect_equal(selectedRootOf(app), "data")
  expect_false(warningShown(app))
})

test_that("a dotdot escape in the dir chooser does not leak or wedge the session", {
  skipUnlessBrowser()
  app <- AppDriver$new(appDir, name = "dir-typed-dotdot", load_timeout = 30000)
  on.exit(app$stop(), add = TRUE)

  openChooser(app, "dir")
  typeIntoPathBox(app, "../../..")

  expect_false(grepl("elsewhere", visibleDirNames(app), fixed = TRUE))

  typeIntoPathBox(app, fs::path(base, "data", "images"))
  expect_equal(selectedRootOf(app), "data")
})

# --- file chooser -----------------------------------------------------------

test_that("an absolute path typed into the file chooser resolves and switches root", {
  skipUnlessBrowser()
  app <- AppDriver$new(appDir, name = "file-typed-abs", load_timeout = 30000)
  on.exit(app$stop(), add = TRUE)

  openChooser(app, "file")
  typeIntoPathBox(app, fs::path(base, "data"))

  listing <- app$get_js("
    $('.sF-modalContainer:visible').last()
      .find('.sF-fileList .sF-file-name').map(function(){
        return $(this).text().trim();
      }).toArray().join(',')
  ")
  expect_match(listing, "readme.txt")
})

test_that("a typed file path is returned by parseFilePaths", {
  skipUnlessBrowser()
  app <- AppDriver$new(appDir, name = "file-typed-parse", load_timeout = 30000)
  on.exit(app$stop(), add = TRUE)

  openChooser(app, "file")
  typeIntoPathBox(app, fs::path(base, "data", "documents"))

  app$run_js("
    var modal = $('.sF-modalContainer:visible').last();
    var el = modal.find('.sF-fileList').children().filter(function(){
      return $(this).text().indexOf('notes.txt') !== -1;
    })[0];
    // The row handler is delegated and reads a real event, so a jQuery
    // trigger on the row does not select it.
    el.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true}));
  ")
  app$wait_for_idle()
  clickSelect(app)

  expect_equal(
    app$get_value(output = "filepath"),
    as.character(fs::path(base, "data", "documents", "notes.txt"))
  )
})

test_that("a file path outside every root does not navigate", {
  skipUnlessBrowser()
  app <- AppDriver$new(appDir, name = "file-typed-escape", load_timeout = 30000)
  on.exit(app$stop(), add = TRUE)

  openChooser(app, "file")
  typeIntoPathBox(app, "/etc")

  expect_true(warningShown(app))

  typeIntoPathBox(app, fs::path(base, "data"))
  expect_false(warningShown(app))
})
