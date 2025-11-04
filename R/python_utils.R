#' Check if Python has venv module available
#'
#' @param python_cmd Python command to check (default: "python3")
#' @return Logical indicating if venv module is available
#' @noRd
python_has_venv <- function(python_cmd = "python3") {
  # Check if python command exists
  if (Sys.which(python_cmd) == "") {
    return(FALSE)
  }

  # Try to import venv module
  result <- tryCatch(
    {
      status <- system2(
        python_cmd,
        c("-c", "import venv"),
        stdout = FALSE,
        stderr = FALSE
      )
      status == 0
    },
    error = function(e) {
      FALSE
    }
  )

  return(result)
}

#' Check if system requirements for Mojo compilation are available
#'
#' @return Named logical vector with availability of requirements
#' @export
mojo_check_python_requirements <- function() {
  # Check each requirement individually and ensure logical result
  python3_available <- tryCatch(
    {
      path <- Sys.which("python3")
      !is.na(path) && path != ""
    },
    error = function(e) FALSE
  )

  python3_venv_available <- tryCatch(
    {
      if (python3_available) {
        python_has_venv("python3")
      } else {
        FALSE
      }
    },
    error = function(e) FALSE
  )

  pip_available <- tryCatch(
    {
      pip_path <- Sys.which("pip")
      pip3_path <- Sys.which("pip3")
      (!is.na(pip_path) && pip_path != "") ||
        (!is.na(pip3_path) && pip3_path != "")
    },
    error = function(e) FALSE
  )

  requirements <- c(
    python3 = python3_available,
    python3_venv = python3_venv_available,
    pip = pip_available
  )

  return(requirements)
}
