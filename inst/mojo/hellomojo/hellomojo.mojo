# Mojo code for hello world and addition functions
# exported to c
# load necessary FFI types for accessing R C API functions
# since we are in the same adress space as R when calling these functions
from sys.ffi import DLHandle, c_char, c_int

# Rprintf type: takes a C string pointer, returns int
alias Rprintf_type = fn(fmt: UnsafePointer[c_char]) -> c_int

@export
fn hello(msg: UnsafePointer[c_char]):
    try:
        # Access global symbols in running R process
        var handle: DLHandle = DLHandle("")
        # Lookup Rprintf
        var Rprintf = handle.get_function[Rprintf_type]("Rprintf")
        # Directly call Rprintf using the passed pointer
        _ = Rprintf(msg)
    except:
        # Silently ignore if not running in R
        return

@export
fn add( a: Float64, b: Float64) -> Float64:
    return a + b

@export
fn convolve(signal: UnsafePointer[Float64], signal_len: Int, kernel: UnsafePointer[Float64], kernel_len: Int, output: UnsafePointer[Float64]):
    i: Int = 0
    while i < signal_len - kernel_len + 1:
        acc: Float64 = 0.0
        j: Int = 0
        while j < kernel_len:
            acc = acc + (signal + i + j)[] * (kernel + j)[]
            j = j + 1
        (output + i)[] = acc
        i = i + 1
