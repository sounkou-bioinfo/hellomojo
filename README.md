
# hellomojo

An Example R Package that Uses ‘mojo’ Through the `.Call` Interface

## Overview

This package provides a setup to call
[Mojo](https://www.modular.com/mojo) code from R using the mojo shared
library build mode. This was obviously designed for python interop. If
we only use simple types, we can call mojo using the `.Call` interface.
Some boilerplate is required, but this can be automated.

## How It Works ?

Mojo code is compiled to a shared library, in our case `libhello.so`. A
C file [`RC_hellomojo.c`](src/RC_hellomojo.c) provides wrappers and
registration so R can call the Mojo functions via the `.Call` interface.
R functions like `hellomojo()` call the native code using `.Call()` and
R C API can be called (somehow unsafely from Mojo). The
[`configure`](configure) script uses [pixi](https://pixi.sh/) to install
mojo and run the shared library build.

## Installation

By default, the package installs without Mojo installation via pixi

``` r
install.packages('hellomojo', repos = c('https://sounkou-bioinfo.r-universe.dev', 'https://cloud.r-project.org'))
```

To enable compiling the Mojo functions with the RC code, set
`HELLOMOJO_BUILD=1` before installation. The configure script will
automatically install pixi and compile the hellomojo shared library:

``` r
Sys.setenv(HELLOMOJO_BUILD = "1")
install.packages('hellomojo', repos = c('https://sounkou-bioinfo.r-universe.dev', 'https://cloud.r-project.org'))
```

For dynamic compilation workflows similar to `callme::compile()`,
install Mojo in a virtual environment first:

``` r
mojo_install(venv = ".venv/mojo", nightly = TRUE)
mojo_compile("inst/mojo/hellomojo/hellomojo.mojo", venv = ".venv/mojo")
```

## Example with pre-compiled native functions

``` r
# Load the package and call the native function
hellomojo::hellomojo()
#> hello from R via Mojo!
hellomojo::hellomojo_add(10, 30)
#> [1] 40

# Get comprehensive system and device information (CPU + GPU when available)
# hellomojo::hellomojo_device_info(device_id = 0L, api_name = "cuda")
```

the mojo code

``` bash
cat inst/mojo/hellomojo/hellomojo.mojo
# Mojo code for hello world and addition functions
# exported to c
# load necessary FFI types for accessing R C API functions
# since we are in the same adress space as R when calling these functions
from sys.ffi import c_char, c_int
from sys.ffi import external_call
from memory.unsafe_pointer import UnsafePointer
from sys import CompilationTarget, num_logical_cores, num_physical_cores

# Rprintf type: takes a C string pointer, returns int
alias Rprintf_type = fn(UnsafePointer[c_char]) -> c_int

@export
fn hello(msg: UnsafePointer[c_char]):
    # Use external_call to call Rprintf directly
    _ = external_call["Rprintf", c_int](msg)

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

@export
fn device_info(device_id: Int32, api_name: UnsafePointer[c_char]):
    # Always show CPU information first
    _ = external_call["Rprintf", c_int]("=== System Information ===\n".unsafe_ptr())
    
    # Simple OS detection
    var os_name = "unix"
    if CompilationTarget.is_linux():
        os_name = "linux"
    elif CompilationTarget.is_macos():
        os_name = "macOS"
        
    # Get CPU architecture 
    var cpu_arch = CompilationTarget._arch()
    
    # Determine CPU features
    var cpu_features = String()
    if CompilationTarget.has_sse4():
        cpu_features += " sse4"
    if CompilationTarget.has_avx():
        cpu_features += " avx"
    if CompilationTarget.has_avx2():
        cpu_features += " avx2"
    if CompilationTarget.has_avx512f():
        cpu_features += " avx512f"
    if CompilationTarget.has_neon():
        cpu_features += " neon"
    if CompilationTarget.is_apple_silicon():
        cpu_features += " apple_silicon"
    
    # Print CPU information
    _ = external_call["Rprintf", c_int]("CPU Information:\n".unsafe_ptr())
    var os_msg = "  OS             : " + os_name + "\n"
    _ = external_call["Rprintf", c_int](os_msg.unsafe_ptr())
    var cpu_msg = "  CPU Arch       : " + String(cpu_arch) + "\n"
    _ = external_call["Rprintf", c_int](cpu_msg.unsafe_ptr())
    var phys_cores_msg = "  Physical Cores : " + String(num_physical_cores()) + "\n"
    _ = external_call["Rprintf", c_int](phys_cores_msg.unsafe_ptr())
    var log_cores_msg = "  Logical Cores  : " + String(num_logical_cores()) + "\n"
    _ = external_call["Rprintf", c_int](log_cores_msg.unsafe_ptr())
    var features_msg = "  CPU Features   :" + cpu_features + "\n"
    _ = external_call["Rprintf", c_int](features_msg.unsafe_ptr())
    
    # GPU status message
    _ = external_call["Rprintf", c_int]("\nGPU Information:\n".unsafe_ptr())
    _ = external_call["Rprintf", c_int]("  Status         : GPU detection requires additional Mojo modules\n".unsafe_ptr())
```

the C wrappers

``` bash
cat src/RC_hellomojo.c
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

#ifndef HELLOMOJO_NO_BUILD
extern void hello(const char *msg);
extern double add(double a, double b);
extern void convolve(const double *signal, int signal_len,
        const double *kernel, int kernel_len, double *output);
extern void device_info(int device_id, const char *api_name);
#endif

// .Call wrapper for hello 
SEXP hello_call(SEXP msg) {
#ifndef HELLOMOJO_NO_BUILD
    PROTECT(msg);
    if (!isString(msg) || LENGTH(msg) != 1) {
        UNPROTECT(1);
        Rf_error("msg must be a single string");
    }

    const char *cmsg = CHAR(STRING_ELT(msg, 0));
    hello(cmsg);

    UNPROTECT(1);
    return R_NilValue;
#else
    Rf_error("Mojo library not available");
    return R_NilValue;
#endif
}
// .Call wrapper for the Mojo add function
SEXP add_call(SEXP a, SEXP b) {
#ifndef HELLOMOJO_NO_BUILD
    PROTECT(a);
    PROTECT(b);
    if (!isReal(a) && !isInteger(a)) {
        UNPROTECT(2);
        Rf_error("a must be numeric");
    }
    if (!isReal(b) && !isInteger(b)) {
        UNPROTECT(2);
        Rf_error("b must be numeric");
    }
    
    double ad = asReal(a);
    double bd = asReal(b);
    double result = add(ad, bd);
    
    SEXP out = PROTECT(ScalarReal(result));
    UNPROTECT(3);
    return out;
#else
    Rf_error("Mojo library not available");
    return R_NilValue;
#endif
}

// .Call wrapper for the Mojo convolution function
SEXP convolve_call(SEXP signal, SEXP kernel) {
#ifndef HELLOMOJO_NO_BUILD
    PROTECT(signal);
    PROTECT(kernel);
    
    R_xlen_t n_signal = XLENGTH(signal);
    R_xlen_t n_kernel = XLENGTH(kernel);
    
    if (!isReal(signal) || !isReal(kernel)) {
        UNPROTECT(2);
        Rf_error("Both signal and kernel must be numeric vectors");
    }
    if (n_signal < n_kernel) {
        UNPROTECT(2);
        Rf_error("Signal length must be >= kernel length");
    }
    
    R_xlen_t n_out = n_signal - n_kernel + 1;
    SEXP out = PROTECT(allocVector(REALSXP, n_out));
    
    convolve(REAL(signal), n_signal, REAL(kernel), n_kernel, REAL(out));
    
    UNPROTECT(3);
    return out;
#else
    Rf_error("Mojo library not available");
    return R_NilValue;
#endif
}

// .Call wrapper for the Mojo device_info function
SEXP device_info_call(SEXP device_id_r, SEXP api_name_r) {
#ifndef HELLOMOJO_NO_BUILD
    PROTECT(device_id_r);
    PROTECT(api_name_r);
    
    if (!isInteger(device_id_r) && !isReal(device_id_r)) {
        UNPROTECT(2);
        Rf_error("device_id must be numeric");
    }
    if (!isString(api_name_r) || LENGTH(api_name_r) != 1) {
        UNPROTECT(2);
        Rf_error("api_name must be a single string");
    }
    
    int device_id = asInteger(device_id_r);
    const char *api_name = CHAR(STRING_ELT(api_name_r, 0));
    
    device_info(device_id, api_name);
    
    UNPROTECT(2);
    return R_NilValue;
#else
    Rf_error("Mojo library not available");
    return R_NilValue;
#endif
}

static const R_CallMethodDef CallEntries[] = {
    {"hello", (DL_FUNC) &hello_call, 1},
    {"add", (DL_FUNC) &add_call, 2},
    {"convolve", (DL_FUNC) &convolve_call, 2},
    {"device_info", (DL_FUNC) &device_info_call, 2},
    {NULL, NULL, 0}
};
void R_init_hellomojo(DllInfo *dll) {
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, TRUE);
    R_forceSymbols(dll, TRUE);
}
```

## Convolution Example and Benchmark

The classic convolution benchmark

``` r
# Example data
signal <- rnorm(10000)
kernel <- c(0.2, 0.5, 0.3)

# Mojo convolution
mojo_result <- hellomojo::hellomojo_convolve(signal, kernel)

# C convolution using callme
code <- '
  SEXP c_convolve(SEXP signal, SEXP kernel) {
    R_xlen_t n_signal = XLENGTH(signal);
    R_xlen_t n_kernel = XLENGTH(kernel);
    R_xlen_t n_out = n_signal - n_kernel + 1;
    SEXP out = PROTECT(allocVector(REALSXP, n_out));
    double *sig = REAL(signal);
    double *ker = REAL(kernel);
    double *o = REAL(out);
    for (R_xlen_t i = 0; i < n_out; ++i) {
      double acc = 0.0;
      for (R_xlen_t j = 0; j < n_kernel; ++j) {
        acc += sig[i + j] * ker[j];
      }
      o[i] = acc;
    }
    UNPROTECT(1);
    return out;
  }'
callme::compile(code)
c_result <- c_convolve(signal, kernel)

# Check results are similar
print(all.equal(as.numeric(mojo_result), as.numeric(c_result)))
#> [1] TRUE
mojo_result |> head()
#> [1] -1.02102432 -0.44155589 -0.02388847 -0.69692555 -1.42213403 -0.58529291
# Benchmark
bench::mark(
        mojo = hellomojo::hellomojo_convolve(signal, kernel),
        c = c_convolve(signal, kernel),
        check = FALSE
)    
#> # A tibble: 2 × 6
#>   expression      min   median `itr/sec` mem_alloc `gc/sec`
#>   <bch:expr> <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl>
#> 1 mojo         10.9µs   24.3µs    40829.    78.2KB     57.2
#> 2 c              10µs   32.8µs    31983.    78.2KB     44.8
```

## Dynamic Mojo Compilation

You can also compile and load Mojo code dynamically, similar to
`callme::compile()`:

``` r
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
hellomojo::mojo_install(venv = venv_path, nightly = TRUE)
#> Creating virtual environment at: /tmp/Rtmptj2dQT/mojo_venv_14f0d51a7b1462
#> Installing Mojo nightly build...
#> Mojo installed successfully at: /tmp/Rtmptj2dQT/mojo_venv_14f0d51a7b1462/bin/mojo

# Check the size of the Mojo installation
venv_size <- system2("du", c("-sh", venv_path), stdout = TRUE)
venv_size
#> [1] "691M\t/tmp/Rtmptj2dQT/mojo_venv_14f0d51a7b1462"

# Compile the Mojo file and get R functions
hellomojo::mojo_compile(
  temp_mojo,
  venv = venv_path,
  verbosity = 1
)
#> Using Mojo: /tmp/Rtmptj2dQT/mojo_venv_14f0d51a7b1462/bin/mojo
#> Parsing Mojo file: /tmp/Rtmptj2dQT/file14f0d51d685e02.mojo
#> Parsing arg: [ x: Float64 ]
#>   -> name=[ x ] type=[ Float64 ]
#> Parsing arg: [ y: Float64 ]
#>   -> name=[ y ] type=[ Float64 ]
#> Parsing arg: [ name: UnsafePointer[c_char] ]
#>   -> name=[ name ] type=[ UnsafePointer[c_char] ]
#> Compiling Mojo to shared library...
#> Generating C wrappers...
#> Compiling C wrappers...
#> Compiling C wrappers...
#> Loading compiled library...
#> Loading DLL: /tmp/Rtmptj2dQT/mojo_compile_14f0d542d4d76/mojo_wrappers.so
#> Success! 2 function(s) available.

# Now the @export functions are available:
multiply(6.0, 7.0)
#> [1] 42
greet("Hello from dynamically compiled Mojo!")
#> Hello from dynamically compiled Mojo!
#> NULL

unlink(temp_mojo)
unlink(venv_path, recursive = TRUE)
```

## System and Device Information with Dynamic Compilation

Here’s how to get comprehensive system and GPU device information using
dynamic Mojo compilation:

``` r
# Create Mojo code for system and device info
device_info_mojo <- '
from sys.ffi import DLHandle, c_char, c_int
import gpu.host
from sys import CompilationTarget, num_logical_cores, num_physical_cores
from sys.info import _triple_attr

alias Rprintf_type = fn(fmt: UnsafePointer[c_char]) -> c_int

fn compute_capability_to_arch_name(major: Int, minor: Int) -> String:
    if major == 1:
        return "tesla"
    if major == 2:
        return "fermi"
    if major == 3:
        return "kepler"
    # ... more architectures
    return "Unknown"

@export
fn system_info(device_id: Int32, api_name: UnsafePointer[c_char]):
    try:
        var handle: DLHandle = DLHandle("")
        var Rprintf = handle.get_function[Rprintf_type]("Rprintf")
        
        _ = Rprintf("=== System Information ===\\n")
        
        # CPU info always shown
        var os_name = "linux"  # simplified
        var cpu = CompilationTarget._arch()
        
        _ = Rprintf("CPU Information:\\n")
        var os_msg = "  OS             : " + os_name + "\\n"
        _ = Rprintf(os_msg.unsafe_ptr())
        var cpu_msg = "  CPU            : " + String(cpu) + "\\n"
        _ = Rprintf(cpu_msg.unsafe_ptr())
        
        # Try GPU info
        try:
            var api = String(api_name)
            var ctx = gpu.host.DeviceContext(Int(device_id), api=api)
            _ = Rprintf("\\nGPU Information:\\n")
            var name_msg = "  Name           : " + ctx.name() + "\\n"
            _ = Rprintf(name_msg.unsafe_ptr())
        except:
            _ = Rprintf("\\nGPU Information:\\n")
            _ = Rprintf("  Status         : No GPU detected\\n")
    except:
        pass
'

# Write to temporary file
temp_mojo_system <- tempfile(fileext = ".mojo")
writeLines(device_info_mojo, temp_mojo_system)

# Compile and load
hellomojo::mojo_compile(temp_mojo_system, venv = venv_path)

# Get comprehensive system info (CPU always, GPU when available)
system_info(0L, "cuda")

unlink(temp_mojo_system)
```

This parses the Mojo file, extracts all `@export` functions, generates C
wrappers, compiles everything, and creates R functions automatically.
Only `UnsafePointer` types and scalar Int/Float types are currently
supported. This is quite brittle now. We should use a proper Mojo parser
or dump MLIR representations like in this
[gist](https://gist.github.com/soraros/44d56698cb20a6c5db3160f13ca81675)

## Limitations to investigate

The package now offers two approaches: the original pixi-based static
compilation and a dynamic compilation system using Python virtual
environments. For compilation at installation time, we use pixi to get
Mojo binaries, but installing this on the R Windows toolchain is not
straightforward. We should consider using uv or creating an R package
that installs pixi. Moreover, Windows support could not be added to the
current pixi workspace (because Mojo only supports WSL). This package
should work fine on Unix systems.

The dynamic compilation approach (`mojo_compile()`) provides a more
lightweight alternative that only requires a Python virtual environment
with Mojo installed, avoiding the need for pixi entirely. This makes the
installation much more manageable and potentially Windows-compatible (if
Mojo support windows).

We are calling the Mojo shared object in the same address space as R and
calling the R C API from Mojo FFI, even though the toolchains are
different.

The main limitation remains that the pixi strategy downloads the entire
Mojo runtime and toolchain (essentially installing LLVM), leading to a
~1GB install. The dynamic approach mitigates this by allowing users to
manage Mojo installation separately at runtime(still big tough).

## References

- [Mojo Getting Started
  Guide](https://docs.modular.com/mojo/manual/get-started)  
- [pixi: Package and Environment Manager](https://pixi.sh/)
- [simpleCall example](https://github.com/coolbutuseless/simpleCall)
