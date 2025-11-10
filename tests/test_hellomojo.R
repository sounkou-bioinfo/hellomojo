# Dynamic Mojo compilation test
library(hellomojo)

# Check if system requirements are available
requirements <- NULL
try(
  requirements <- hellomojo::mojo_check_python_requirements()
)
if (is.null(requirements)) {
  cat("Skipping Mojo tests: unable to determine Python requirements\n")
  quit(status = 0)
}
# Ensure we have valid logical values
python3_ok <- isTRUE(requirements[["python3"]])
venv_ok <- isTRUE(requirements[["python3_venv"]])

if (!python3_ok) {
  cat("Skipping Mojo tests: python3 not available\n")
  quit(status = 0)
}

if (!venv_ok) {
  cat("Skipping Mojo tests: python3-venv module not available\n")
  cat("Install with: sudo apt-get install python3-venv (Ubuntu/Debian)\n")
  cat("or: sudo yum install python3-venv (RHEL/CentOS)\n")
  quit(status = 0)
}

cat("Python requirements satisfied, proceeding with Mojo tests...\n")

# Create a simple Mojo file
mojo_code <- '
from sys.ffi import DLHandle, c_char, c_int
alias Rprintf_type = fn(fmt: UnsafePointer[c_char]) -> c_int
@export
fn multiply(x: Float64, y: Float64) -> Float64:
    return x * y

@export
fn greet(name: UnsafePointer[c_char]):
    try:
        var handle: DLHandle = DLHandle("")
        var Rprintf = handle.get_function[Rprintf_type]("Rprintf")
        _ = Rprintf(name)
    except:
        return
'

# Write to temporary file
temp_mojo <- tempfile(fileext = ".mojo")
writeLines(mojo_code, temp_mojo)

# Install Mojo in a temporary venv (only needed once)
venv_path <- tempfile(pattern = "mojo_venv_")
# check if  install succeeds, otherwise skip tests
path <- NULL
try(
  path <- hellomojo::mojo_install(venv = venv_path, nightly = TRUE)
)
if (is.null(path)) {
  cat("Skipping Mojo tests: installation failed\n")
  quit(status = 0)
}
Sys.sleep(5)

# Check the size of the Mojo installation
venv_size <- system2("du", c("-sh", venv_path), stdout = TRUE)
venv_size
Sys.sleep(5)

hellomojo::mojo_compile(
  temp_mojo,
  venv = venv_path,
  verbosity = 4
)
Sys.sleep(5)
multiply(6.0, 7.0)
greet("Hello from dynamically compiled Mojo!\\n")
stopifnot(
  multiply(6.0, 7.0) == 42.0
)

unlink(temp_mojo)
unlink(venv_path, recursive = TRUE)
