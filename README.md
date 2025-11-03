
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
install.packages(".", repos = NULL, type = "source")
```

To enable compiling the Mojo functions with the RC code, set
`HELLOMOJO_BUILD=1` before installation. The configure script will
automatically install pixi and compile the hellomojo shared library:

``` r
Sys.setenv(HELLOMOJO_BUILD = "1")
install.packages(".", repos = NULL, type = "source")
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
```

the mojo code

``` bash
cat inst/mojo/hellomojo/hellomojo.mojo
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
#endif

// .Call wrapper for hello 
SEXP hello_call(SEXP msg) {
#ifndef HELLOMOJO_NO_BUILD
    if (!isString(msg) || LENGTH(msg) != 1)
        Rf_error("msg must be a single string");

    const char *cmsg = CHAR(STRING_ELT(msg, 0));
    hello(cmsg);

    return R_NilValue;
#else
    Rf_error("Mojo library not available");
    return R_NilValue;
#endif
}
// .Call wrapper for the Mojo add function
SEXP add_call(SEXP a, SEXP b) {
#ifndef HELLOMOJO_NO_BUILD
    double ad = asReal(a);
    double bd = asReal(b);
    double result = add(ad, bd);
    return ScalarReal(result);
#else
    Rf_error("Mojo library not available");
    return R_NilValue;
#endif
}

// .Call wrapper for the Mojo convolution function
SEXP convolve_call(SEXP signal, SEXP kernel) {
#ifndef HELLOMOJO_NO_BUILD
    R_xlen_t n_signal = XLENGTH(signal);
    R_xlen_t n_kernel = XLENGTH(kernel);
    if (!isReal(signal) || !isReal(kernel))
        Rf_error("Both signal and kernel must be numeric vectors");
    if (n_signal < n_kernel)
        Rf_error("Signal length must be >= kernel length");
    R_xlen_t n_out = n_signal - n_kernel + 1;
    SEXP out = PROTECT(allocVector(REALSXP, n_out));
    convolve(REAL(signal), n_signal, REAL(kernel), n_kernel, REAL(out));
    UNPROTECT(1);
    return out;
#else
    Rf_error("Mojo library not available");
    return R_NilValue;
#endif
}

static const R_CallMethodDef CallEntries[] = {
    {"hello", (DL_FUNC) &hello_call, 1},
    {"add", (DL_FUNC) &add_call, 2},
    {"convolve", (DL_FUNC) &convolve_call, 2},
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
#> [1] -0.2814557 -0.1837509 -0.1537883 -0.2562482 -0.1701348  0.1851902
# Benchmark
bench::mark(
        mojo = hellomojo::hellomojo_convolve(signal, kernel),
        c = c_convolve(signal, kernel),
        check = FALSE
)    
#> # A tibble: 2 × 6
#>   expression      min   median `itr/sec` mem_alloc `gc/sec`
#>   <bch:expr> <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl>
#> 1 mojo         10.8µs   24.4µs    40568.    78.2KB     56.9
#> 2 c              10µs   32.9µs    31947.    78.2KB     44.8
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
#> Creating virtual environment at: /tmp/RtmpIB80FD/mojo_venv_11778e5c5fa038
#> Installing Mojo nightly build...
#> Mojo installed successfully at: /tmp/RtmpIB80FD/mojo_venv_11778e5c5fa038/bin/mojo

# Check the size of the Mojo installation
venv_size <- system2("du", c("-sh", venv_path), stdout = TRUE)
venv_size
#> [1] "691M\t/tmp/RtmpIB80FD/mojo_venv_11778e5c5fa038"

# Compile the Mojo file and get R functions
hellomojo::mojo_compile(
  temp_mojo,
  venv = venv_path,
  verbosity = 1
)
#> Using Mojo: /tmp/RtmpIB80FD/mojo_venv_11778e5c5fa038/bin/mojo
#> Parsing Mojo file: /tmp/RtmpIB80FD/file11778e2c8431c2.mojo
#> Parsing arg: [ x: Float64 ]
#>   -> name=[ x ] type=[ Float64 ]
#> Parsing arg: [ y: Float64 ]
#>   -> name=[ y ] type=[ Float64 ]
#> Parsing arg: [ name: UnsafePointer[c_char] ]
#>   -> name=[ name ] type=[ UnsafePointer[c_char] ]
#> Compiling Mojo to shared library...
#> Generating C wrappers...
#> Compiling C wrappers...
#> Loading compiled library...
#> Loading DLL: /tmp/RtmpIB80FD/mojo_compile_11778e538c99c4/mojo_wrappers.so
#> Success! 2 function(s) available.

# Now the @export functions are available:
multiply(6.0, 7.0)
#> [1] 42
greet("Hello from dynamically compiled Mojo!\\n")
#> Hello from dynamically compiled Mojo!\n
#> NULL

# Clean up
unlink(temp_mojo)
unlink(venv_path, recursive = TRUE)
```

This parses the Mojo file, extracts all `@export` functions, generates C
wrappers, compiles everything, and creates R functions automatically.
Only `UnsafePointer` types and scalar Int/Float types are currently
supported. This is quite brittle now.

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
