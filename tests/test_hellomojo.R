# Create a simple Mojo file
library(hellomojo)
mojo_code <- '
from sys.ffi import DLHandle, c_char, c_int
alias Rprintf_type = fn(fmt: UnsafePointer[c_char]) -> c_int
@export
fn multiply(x: Float64, y: Float64) -> Float64:
    return x * y

@export
fn greet(name: UnsafePointer[c_char]):

    alias Rprintf_type = fn(fmt: UnsafePointer[c_char]) -> c_int
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
hellomojo::mojo_install(venv = venv_path, nightly = TRUE)
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
