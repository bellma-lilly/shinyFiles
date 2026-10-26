# Cost of each click in an open folder chooser.
#
#   Rscript bench/click-benchmark.R <label> [root]
#
# Drives shinyDirChoose() through shiny::testServer() and plays the client's
# side faithfully: every request is the last response, round-tripped through
# Shiny's own JSON encoding, with the one field the click changes. Each step
# is bracketed by markers on stderr so bench/strace-count.sh can attribute
# syscalls to it. The root should have folder01..folder03, each with child1
# (bench/make-fixture.R builds one).

args <- commandArgs(trailingOnly = TRUE)
label <- if (length(args) >= 1) args[[1]] else "run"
root <- if (length(args) >= 2) args[[2]] else "bench/fixture"
root <- as.character(fs::path_real(root))

suppressMessages(pkgload::load_all(".", quiet = TRUE, export_all = TRUE))
suppressMessages(library(shiny))

marker <- function(text) cat(sprintf("@@SF-BENCH %s@@\n", text), file = stderr())

# What the browser would hold after receiving a message.
roundTrip <- function(x) {
  jsonlite::fromJSON(as.character(shiny:::toJSON(x)), simplifyVector = FALSE)
}

steps <- list()

server <- function(input, output, session) {
  shinyDirChoose(input, "dir", roots = c(bench = root), session = session)
}

testServer(server, {
  last <- NULL
  session$sendCustomMessage <- function(type, message) last <<- roundTrip(message$dir)

  # Walks the tree the client holds and flips one node, as toggleExpander does.
  toggle <- function(tree, path) {
    if (length(path) == 0) {
      tree$expanded <- !isTRUE(tree$expanded)
      return(tree)
    }
    i <- which(vapply(tree$children, function(ch) identical(ch$name, path[[1]]), logical(1)))
    tree$children[[i]] <- toggle(tree$children[[i]], path[-1])
    tree
  }

  step <- function(name, expr) {
    marker(paste("begin", name))
    t <- system.time(force(expr))[["elapsed"]]
    marker(paste("end", name))
    steps[[length(steps) + 1]] <<- data.frame(step = name, seconds = t)
  }

  send <- function(data) session$setInputs(`dir-modal` = data)
  # modifyList() would merge the tree recursively; the client replaces it.
  with <- function(field, value) {
    data <- last
    data[field] <- list(value)
    data
  }

  step("open", session$setInputs(dir = 1))
  # The first response after opening carries no tree state yet; the client
  # sends the root expanded with nothing highlighted.
  send(c(last[setdiff(names(last), c("tree", "contentPath"))],
         list(tree = list(name = "", expanded = TRUE), contentPath = NULL)))

  step("expand_folder01", send(with("tree", toggle(last$tree, list("folder01")))))
  step("expand_folder02", send(with("tree", toggle(last$tree, list("folder02")))))
  step("expand_folder01_child1", send(with("tree", toggle(last$tree, list("folder01", "child1")))))
  step("highlight_folder03", send(with("contentPath", list("", "folder03"))))
  step("expand_folder03", send(with("tree", toggle(last$tree, list("folder03")))))
  step("highlight_folder01", send(with("contentPath", list("", "folder01"))))
  step("collapse_folder02", send(with("tree", toggle(last$tree, list("folder02")))))
})

steps <- do.call(rbind, steps)
write.csv(steps, file.path("bench", "results", paste0(label, "-clicks.csv")), row.names = FALSE)
print(steps)
