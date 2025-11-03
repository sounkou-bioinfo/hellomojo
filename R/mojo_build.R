#' Find Mojo binary in virtual environment or system
#'
#' @param venv Path to virtual environment. If NULL, searches system PATH.
#' @return Path to mojo binary, or NULL if not found
#' @export
mojo_find <- function(venv = NULL) {
  if (!is.null(venv)) {
    mojo_path <- file.path(venv, "bin", "mojo")
    if (file.exists(mojo_path)) {
      return(normalizePath(mojo_path))
    }
  }

  # Check system PATH
  mojo_path <- Sys.which("mojo")
  if (nzchar(mojo_path)) {
    return(as.character(mojo_path))
  }

  NULL
}

#' Create a Python virtual environment and install Mojo
#'
#' @param venv Path where to create the virtual environment
#' @param nightly If TRUE, install nightly build. If FALSE, install stable.
#' @param python Python executable to use. Default is "python3".
#' @export
mojo_install <- function(
  venv = ".venv/mojo",
  nightly = TRUE,
  python = "python3"
) {
  if (dir.exists(venv)) {
    message("Virtual environment already exists at: ", venv)
  } else {
    message("Creating virtual environment at: ", venv)
    status <- system2(python, c("-m", "venv", venv))
    if (status != 0) {
      stop("Failed to create virtual environment")
    }
  }

  # Activate and install mojo
  pip <- file.path(venv, "bin", "pip")
  if (!file.exists(pip)) {
    stop("pip not found in virtual environment")
  }

  message("Installing Mojo ", if (nightly) "nightly" else "stable", " build...")

  if (nightly) {
    status <- system2(
      pip,
      c(
        "install",
        "mojo",
        "--extra-index-url",
        "https://modular.gateway.scarf.sh/simple/"
      )
    )
  } else {
    status <- system2(
      pip,
      c(
        "install",
        "mojo",
        "--extra-index-url",
        "https://modular.gateway.scarf.sh/simple/"
      )
    )
  }

  if (status != 0) {
    stop("Failed to install Mojo")
  }

  # Verify installation
  mojo_path <- mojo_find(venv)
  if (is.null(mojo_path)) {
    stop("Mojo installed but binary not found")
  }

  message("Mojo installed successfully at: ", mojo_path)

  # Print version
  system2(mojo_path, "--version")

  invisible(mojo_path)
}

#' Compile Mojo source file to shared library
#'
#' @param source Path to .mojo source file
#' @param output Path for output shared library
#' @param venv Path to virtual environment with Mojo. If NULL, uses system mojo.
#' @export
mojo_compile <- function(source, output = NULL, venv = NULL) {
  if (!file.exists(source)) {
    stop("Source file not found: ", source)
  }

  mojo_path <- mojo_find(venv)
  if (is.null(mojo_path)) {
    stop("Mojo not found. Install with mojo_install() or set venv parameter.")
  }

  if (is.null(output)) {
    # Default output name
    output <- sub("\\.mojo$", "", source)
    libsuffix <- if (Sys.info()["sysname"] == "Darwin") ".dylib" else ".so"
    output <- paste0(output, libsuffix)
  }

  message("Compiling ", source, " to ", output)

  status <- system2(
    mojo_path,
    c(
      "build",
      source,
      "--emit",
      "shared-lib",
      "-o",
      output
    )
  )

  if (status != 0) {
    stop("Mojo compilation failed")
  }

  if (!file.exists(output)) {
    stop("Compilation succeeded but output file not found")
  }

  message("Successfully compiled to: ", output)
  invisible(output)
}

#' Build Mojo library for this package
#'
#' Compiles the Mojo source and installs it to inst/libs
#'
#' @param venv Path to virtual environment with Mojo
#' @param source Path to Mojo source file
#' @export
mojo_build_package <- function(
  venv = ".venv/mojo",
  source = "inst/mojo/hellomojo/hellomojo.mojo"
) {
  if (!file.exists(source)) {
    stop("Mojo source not found: ", source)
  }

  # Ensure inst/libs exists
  libs_dir <- "inst/libs"
  if (!dir.exists(libs_dir)) {
    dir.create(libs_dir, recursive = TRUE)
  }

  # Determine output path
  libsuffix <- if (Sys.info()["sysname"] == "Darwin") "dylib" else "so"
  output <- file.path(libs_dir, paste0("libhello.", libsuffix))

  # Compile
  mojo_compile(source, output, venv)

  message("\nTo rebuild the package with Mojo support:")
  message("  Sys.setenv(HELLOMOJO_BUILD = '1')")
  message("  install.packages('.', repos = NULL, type = 'source')")

  invisible(output)
}

#' Get information about Mojo installation
#'
#' @param venv Path to virtual environment
#' @export
mojo_info <- function(venv = NULL) {
  mojo_path <- mojo_find(venv)

  info <- list(
    found = !is.null(mojo_path),
    path = mojo_path,
    venv = venv
  )

  if (info$found) {
    version_out <- system2(mojo_path, "--version", stdout = TRUE, stderr = TRUE)
    info$version <- paste(version_out, collapse = "\n")
  }

  class(info) <- "mojo_info"
  info
}

#' @export
print.mojo_info <- function(x, ...) {
  cat("Mojo Installation Info\n")
  cat("======================\n\n")
  cat("Found:   ", x$found, "\n")
  if (x$found) {
    cat("Path:    ", x$path, "\n")
    if (!is.null(x$venv)) {
      cat("Venv:    ", x$venv, "\n")
    }
    cat("\nVersion:\n", x$version, "\n")
  } else {
    cat("\nMojo not found. Install with:\n")
    cat("  mojo_install()\n")
  }
  invisible(x)
}
