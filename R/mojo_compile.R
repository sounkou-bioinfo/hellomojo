#' Extract exported functions from Mojo source code
#'
#' Parses a .mojo file and extracts all functions marked with export
#' that have C-compatible types
#'
#' @param mojo_file Path to .mojo source file
#' @return Data frame with columns: name, return_type, args (list)
#' @noRd
mojo_extract_exports <- function(mojo_file) {
  if (!file.exists(mojo_file)) {
    stop("Mojo file not found: ", mojo_file)
  }

  code <- paste(readLines(mojo_file, warn = FALSE), collapse = "\n")

  # Pattern to match @export functions with C-compatible signatures
  # Matches: fn name(arg: Type, ...) -> ReturnType:
  pattern <- "(?ms)@export\\s+fn\\s+([a-zA-Z0-9_]+)\\s*\\(([^)]*)\\)(?:\\s*->\\s*([^:]+))?"

  matches <- gregexpr(pattern, code, perl = TRUE)
  if (matches[[1]][1] == -1) {
    warning("No @export functions found in ", mojo_file)
    return(data.frame(
      name = character(0),
      return_type = character(0),
      args = I(list()),
      stringsAsFactors = FALSE
    ))
  }

  results <- list()

  for (i in seq_along(matches[[1]])) {
    m <- regmatches(code, matches)[[1]][i]

    # Extract function name
    name_match <- regexec("fn\\s+([a-zA-Z0-9_]+)", m, perl = TRUE)
    func_name <- regmatches(m, name_match)[[1]][2]

    # Extract return type
    ret_match <- regexec("->\\s*([^:]+)", m, perl = TRUE)
    if (ret_match[[1]][1] != -1) {
      return_type <- trimws(regmatches(m, ret_match)[[1]][2])
    } else {
      return_type <- "None" # No return type specified
    }

    # Extract arguments
    args_match <- regexec("\\(([^)]*)\\)", m, perl = TRUE)
    args_str <- trimws(regmatches(m, args_match)[[1]][2])

    if (args_str == "") {
      args <- list()
    } else {
      arg_parts <- strsplit(args_str, ",")[[1]]
      args <- lapply(arg_parts, function(arg) {
        arg <- trimws(arg)
        cat("Parsing arg: [", arg, "]\n")
        # Parse "name: Type" format
        parts <- strsplit(arg, ":")[[1]]
        if (length(parts) == 2) {
          name <- trimws(parts[1])
          type <- trimws(parts[2])
          cat("  -> name=[", name, "] type=[", type, "]\n")
          list(name = name, type = type)
        } else {
          cat("  -> invalid format, parts=", length(parts), "\n")
          NULL
        }
      })
      args <- Filter(Negate(is.null), args)
    }

    results[[i]] <- list(
      name = func_name,
      return_type = return_type,
      args = list(args)
    )
  }

  # Convert to data frame properly handling list columns
  data.frame(
    name = sapply(results, `[[`, "name"),
    return_type = sapply(results, `[[`, "return_type"),
    args = I(lapply(results, `[[`, "args")),
    stringsAsFactors = FALSE
  )
}


#' Map Mojo types to C types (pointer types only)
#'
#' We only support UnsafePointer types for now as these work reliably
#' with the R C API. Passing C types by value from Mojo is untested.
#'
#' @noRd
mojo_type_to_c <- function(mojo_type) {
  # Only support UnsafePointer types for now
  type_map <- c(
    "UnsafePointer[Float64]" = "double*",
    "UnsafePointer[Float32]" = "float*",
    "UnsafePointer[Int64]" = "int64_t*",
    "UnsafePointer[Int32]" = "int32_t*",
    "UnsafePointer[Int]" = "int*",
    "UnsafePointer[UInt8]" = "uint8_t*",
    "UnsafePointer[Int8]" = "char*",
    "UnsafePointer[c_char]" = "char*",
    "Float64" = "double",
    "Float32" = "float",
    "Int" = "int", # For sizes/counts
    "Int32" = "int",
    "Int64" = "int64_t",
    "None" = "void"
  )

  result <- type_map[mojo_type]
  if (length(result) == 0 || is.na(result) || is.null(result)) {
    warning(
      "Unsupported Mojo type: ",
      mojo_type,
      ". Only UnsafePointer types and Int sizes are supported."
    )
    return(NULL)
  }
  result
}

#' Null-coalescing operator
#' @noRd
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a)) b else a


#' Generate C wrapper code for Mojo exported functions
#'
#' Creates .Call()-compatible C wrapper functions
#'
#' @param exports Data frame from mojo_extract_exports()
#' @param lib_name Name of the Mojo shared library (without extension)
#' @return Character string containing C code
#' @noRd
mojo_generate_c_wrappers <- function(exports, lib_name = "libhello") {
  if (nrow(exports) == 0) {
    stop("No exports to wrap")
  }

  # Header
  c_code <- c(
    "#include <R.h>",
    "#include <Rinternals.h>",
    "#include <R_ext/Rdynload.h>",
    "",
    "// External declarations for Mojo functions"
  )

  # Extern declarations for each Mojo function
  for (i in seq_len(nrow(exports))) {
    func <- exports[i, ]
    ret_type <- mojo_type_to_c(func$return_type)

    args_c <- sapply(func$args[[1]][[1]], function(arg) {
      c_type <- mojo_type_to_c(arg$type)
      if (is.null(c_type)) {
        stop("Unsupported type in function ", func$name, ": ", arg$type)
      }
      paste(c_type, arg$name)
    })

    if (length(args_c) == 0) {
      args_str <- "void"
    } else {
      args_str <- paste(args_c, collapse = ", ")
    }

    c_code <- c(
      c_code,
      sprintf("extern %s %s(%s);", ret_type, func$name, args_str)
    )
  }

  c_code <- c(c_code, "", "// .Call() wrapper functions")

  # Generate wrapper for each function
  for (i in seq_len(nrow(exports))) {
    func <- exports[i, ]
    wrapper_name <- paste0("call_", func$name)

    # Generate SEXP argument list
    args <- func$args[[1]][[1]]
    n_args <- length(args)
    sexp_args <- if (n_args == 0) {
      ""
    } else {
      paste0(
        "SEXP ",
        sapply(seq_len(n_args), function(j) paste0("arg", j)),
        collapse = ", "
      )
    }

    c_code <- c(c_code, "", sprintf("SEXP %s(%s) {", wrapper_name, sexp_args))

    # Protect all input SEXPs
    if (n_args > 0) {
      for (j in seq_len(n_args)) {
        c_code <- c(c_code, sprintf("  PROTECT(arg%d);", j))
      }
    }

    # Convert SEXP to C types with validation
    for (j in seq_along(args)) {
      arg <- args[[j]]
      c_type <- mojo_type_to_c(arg$type)

      if (is.null(c_type)) {
        stop("Unsupported type in function ", func$name, ": ", arg$type)
      }

      # Add input validation
      if (grepl("\\*$", c_type)) {
        base_type <- sub("\\*$", "", c_type)
        if (base_type %in% c("double", "float")) {
          c_code <- c(
            c_code,
            sprintf(
              "  if (!isReal(arg%d)) { UNPROTECT(%d); error(\"Argument %d must be numeric\"); }",
              j,
              n_args,
              j
            )
          )
          conversion <- sprintf("  %s %s = REAL(arg%d);", c_type, arg$name, j)
        } else if (base_type %in% c("int", "int32_t")) {
          c_code <- c(
            c_code,
            sprintf(
              "  if (!isInteger(arg%d)) { UNPROTECT(%d); error(\"Argument %d must be integer\"); }",
              j,
              n_args,
              j
            )
          )
          conversion <- sprintf(
            "  %s %s = INTEGER(arg%d);",
            c_type,
            arg$name,
            j
          )
        } else if (base_type == "char") {
          c_code <- c(
            c_code,
            sprintf(
              "  if (!isString(arg%d)) { UNPROTECT(%d); error(\"Argument %d must be character\"); }",
              j,
              n_args,
              j
            )
          )
          conversion <- sprintf(
            "  const char *%s = CHAR(STRING_ELT(arg%d, 0));",
            arg$name,
            j
          )
        } else {
          conversion <- sprintf(
            "  %s %s = (%s)RAW(arg%d);",
            c_type,
            arg$name,
            c_type,
            j
          )
        }
      } else if (c_type %in% c("int", "int32_t")) {
        c_code <- c(
          c_code,
          sprintf(
            "  if (!isInteger(arg%d) && !isReal(arg%d)) { UNPROTECT(%d); error(\"Argument %d must be numeric\"); }",
            j,
            j,
            n_args,
            j
          )
        )
        conversion <- sprintf(
          "  %s %s = asInteger(arg%d);",
          c_type,
          arg$name,
          j
        )
      } else if (c_type == "double") {
        c_code <- c(
          c_code,
          sprintf(
            "  if (!isReal(arg%d) && !isInteger(arg%d)) { UNPROTECT(%d); error(\"Argument %d must be numeric\"); }",
            j,
            j,
            n_args,
            j
          )
        )
        conversion <- sprintf("  %s %s = asReal(arg%d);", c_type, arg$name, j)
      } else if (c_type == "float") {
        c_code <- c(
          c_code,
          sprintf(
            "  if (!isReal(arg%d) && !isInteger(arg%d)) { UNPROTECT(%d); error(\"Argument %d must be numeric\"); }",
            j,
            j,
            n_args,
            j
          )
        )
        conversion <- sprintf(
          "  %s %s = (float)asReal(arg%d);",
          c_type,
          arg$name,
          j
        )
      } else if (c_type == "int64_t") {
        c_code <- c(
          c_code,
          sprintf(
            "  if (!isReal(arg%d) && !isInteger(arg%d)) { UNPROTECT(%d); error(\"Argument %d must be numeric\"); }",
            j,
            j,
            n_args,
            j
          )
        )
        conversion <- sprintf(
          "  %s %s = (int64_t)asReal(arg%d);",
          c_type,
          arg$name,
          j
        )
      } else {
        stop("Cannot generate conversion for type: ", c_type)
      }

      c_code <- c(c_code, conversion)
    }

    # Call Mojo function
    call_args <- if (n_args == 0) {
      ""
    } else {
      paste(sapply(args, `[[`, "name"), collapse = ", ")
    }
    ret_type <- mojo_type_to_c(func$return_type)

    if (ret_type == "void") {
      c_code <- c(
        c_code,
        sprintf("  %s(%s);", func$name, call_args),
        if (n_args > 0) sprintf("  UNPROTECT(%d);", n_args) else "",
        "  return R_NilValue;"
      )
    } else {
      c_code <- c(
        c_code,
        sprintf("  %s result = %s(%s);", ret_type, func$name, call_args)
      )

      # Convert result to SEXP
      if (grepl("\\*$", ret_type)) {
        # Pointer return - not supported, would need length info
        c_code <- c(
          c_code,
          if (n_args > 0) sprintf("  UNPROTECT(%d);", n_args) else "",
          "  return R_NilValue; // Pointer return not supported"
        )
      } else {
        conversion <- switch(
          ret_type,
          "double" = sprintf(
            "  SEXP out = PROTECT(ScalarReal(result)); UNPROTECT(%d); return out;",
            n_args + 1
          ),
          "float" = sprintf(
            "  SEXP out = PROTECT(ScalarReal((double)result)); UNPROTECT(%d); return out;",
            n_args + 1
          ),
          "int" = sprintf(
            "  SEXP out = PROTECT(ScalarInteger(result)); UNPROTECT(%d); return out;",
            n_args + 1
          ),
          "int32_t" = sprintf(
            "  SEXP out = PROTECT(ScalarInteger((int)result)); UNPROTECT(%d); return out;",
            n_args + 1
          ),
          "int64_t" = sprintf(
            "  SEXP out = PROTECT(ScalarReal((double)result)); UNPROTECT(%d); return out;",
            n_args + 1
          ),
          sprintf(
            "  UNPROTECT(%d); return R_NilValue; // Unsupported return type",
            n_args
          )
        )
        c_code <- c(c_code, conversion)
      }
    }

    c_code <- c(c_code, "}")
  }

  # Registration
  c_code <- c(
    c_code,
    "",
    "// Registration",
    "static const R_CallMethodDef CallEntries[] = {"
  )
  for (i in seq_len(nrow(exports))) {
    func <- exports[i, ]
    wrapper_name <- paste0("call_", func$name)
    n_args <- length(func$args[[1]][[1]])
    c_code <- c(
      c_code,
      sprintf('  {"%s_", (DL_FUNC) &%s, %d},', func$name, wrapper_name, n_args)
    )
  }
  c_code <- c(c_code, "  {NULL, NULL, 0}", "};")

  # Init function - use fixed package name
  pkg_name <- "mojo_wrappers"
  c_code <- c(
    c_code,
    "",
    sprintf("void R_init_%s(DllInfo *dll) {", pkg_name),
    "  R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);",
    "  R_useDynamicSymbols(dll, FALSE);",
    "  R_forceSymbols(dll, FALSE);",
    "}"
  )

  paste(c_code, collapse = "\n")
}


#' Compile Mojo code and create R wrapper functions
#'
#' Similar to `callme::compile()` but for Mojo code.
#' Parses Mojo source, extracts export functions, compiles to shared library,
#' generates C wrappers, compiles those, and creates R functions.
#'
#' @param mojo_file Path to .mojo source file
#' @param venv Path to Python virtual environment with Mojo installed
#' @param PKG_LIBS Additional linker flags (e.g., for external libraries)
#' @param env Environment to assign wrapper functions. Default: parent.frame()
#' @param verbosity Level of output (0-4). Default: 0
#' @return Invisibly returns named list of R wrapper functions
#' @export
mojo_compile <- function(
  mojo_file,
  venv = NULL,
  PKG_LIBS = NULL,
  env = parent.frame(),
  verbosity = 0
) {
  if (!file.exists(mojo_file)) {
    stop("Mojo file not found: ", mojo_file)
  }

  # Find mojo binary
  mojo_path <- mojo_find(venv)
  if (is.null(mojo_path)) {
    stop("Mojo not found. Install with mojo_install() or specify venv.")
  }

  if (verbosity >= 1) {
    message("Using Mojo: ", mojo_path)
  }

  # Extract exported functions
  if (verbosity >= 1) {
    message("Parsing Mojo file: ", mojo_file)
  }
  exports <- mojo_extract_exports(mojo_file)

  if (nrow(exports) == 0) {
    stop("No @export functions found in ", mojo_file)
  }

  if (verbosity >= 2) {
    message("Found ", nrow(exports), " exported function(s):")
    for (i in seq_len(nrow(exports))) {
      message("  - ", exports$name[i])
    }
  }

  # Create temporary directory
  tmp_dir <- tempfile(pattern = "mojo_compile_")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  # Compile Mojo to shared library
  libsuffix <- if (Sys.info()["sysname"] == "Darwin") ".dylib" else ".so"
  mojo_lib <- file.path(tmp_dir, paste0("libmojo", libsuffix))

  if (verbosity >= 1) {
    message("Compiling Mojo to shared library...")
  }

  status <- system2(
    mojo_path,
    c(
      "build",
      mojo_file,
      "--emit",
      "shared-lib",
      "-o",
      mojo_lib
    ),
    stdout = if (verbosity >= 3) "" else FALSE,
    stderr = if (verbosity >= 3) "" else FALSE
  )

  if (status != 0 || !file.exists(mojo_lib)) {
    # Get more detailed error information
    if (verbosity >= 1) {
      message("Mojo compilation failed. Running with verbose output...")
      system2(
        mojo_path,
        c(
          "build",
          mojo_file,
          "--emit",
          "shared-lib",
          "-o",
          mojo_lib
        ),
        stdout = "",
        stderr = ""
      )
    }
    stop("Mojo compilation failed")
  }

  # Generate C wrapper code
  if (verbosity >= 1) {
    message("Generating C wrappers...")
  }
  c_code <- mojo_generate_c_wrappers(exports, "libmojo")
  c_file <- file.path(tmp_dir, "mojo_wrappers.c")
  writeLines(c_code, c_file)

  if (verbosity >= 4) {
    message("Generated C code:")
    cat(c_code, sep = "\n")
  }

  # Compile C wrappers with R CMD SHLIB
  if (verbosity >= 1) {
    message("Compiling C wrappers...")
  }

  # Create Makevars with link to Mojo library
  makevars_content <- sprintf(
    "PKG_LIBS = -L%s -lmojo -Wl,-rpath,%s %s",
    tmp_dir,
    tmp_dir,
    PKG_LIBS %||% ""
  )
  makevars_file <- file.path(tmp_dir, "Makevars")
  writeLines(makevars_content, makevars_file)

  # Compile C wrappers with R CMD SHLIB
  if (verbosity >= 1) {
    message("Compiling C wrappers...")
  }

  # Don't change working directory - use absolute paths instead
  command <- file.path(R.home("bin"), "R")
  args <- c(
    "CMD",
    "SHLIB",
    c_file,
    "-o",
    file.path(tmp_dir, paste0("mojo_wrappers", .Platform$dynlib.ext))
  )

  # Set environment variables for the compilation
  old_makevars <- Sys.getenv("R_MAKEVARS_USER", unset = NA)
  Sys.setenv(R_MAKEVARS_USER = makevars_file)

  tryCatch(
    {
      status <- system2(
        command,
        args,
        stdout = if (verbosity >= 3) "" else FALSE,
        stderr = if (verbosity >= 3) "" else FALSE
      )

      if (status != 0) {
        stop("C wrapper compilation failed")
      }
    },
    finally = {
      # Restore R_MAKEVARS_USER
      if (is.na(old_makevars)) {
        Sys.unsetenv("R_MAKEVARS_USER")
      } else {
        Sys.setenv(R_MAKEVARS_USER = old_makevars)
      }
    }
  )

  dll_file <- file.path(tmp_dir, paste0("mojo_wrappers", .Platform$dynlib.ext))
  if (!file.exists(dll_file)) {
    stop("DLL not created")
  }

  # Load the DLL
  if (verbosity >= 1) {
    message("Loading compiled library...")
  }
  message("Loading DLL: ", dll_file)
  dll_info <- dyn.load(dll_file)

  # Create R wrapper functions
  func_list <- list()
  pkg_name <- basename(tools::file_path_sans_ext(dll_file))

  for (i in seq_len(nrow(exports))) {
    # Extract values immediately to avoid closure issues
    func_name <- exports$name[i]
    n_args <- length(exports$args[[i]][[1]])

    if (n_args == 0) {
      args_str <- ""
      call_args_str <- ""
    } else {
      args_names <- paste0("arg", seq_len(n_args))
      args_str <- paste(args_names, collapse = ", ")
      call_args_str <- paste(args_names, collapse = ", ")
    }

    # Create function string with all values resolved
    func_str <- paste0(
      "function(",
      args_str,
      ") .Call('",
      func_name,
      "_', ",
      call_args_str,
      ")"
    )

    # Parse and create function
    func <- eval(parse(text = func_str))
    class(func) <- c("mojo_function", "function")
    func_list[[func_name]] <- func

    # Assign to environment
    if (!is.null(env)) {
      if (verbosity >= 2) {
        message("Creating R function: ", func_name, "()")
      }
      assign(func_name, func, envir = env)
    }
  }
  if (verbosity >= 1) {
    message("Success! ", nrow(exports), " function(s) available.")
  }

  invisible(func_list)
}
