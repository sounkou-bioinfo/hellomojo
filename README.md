
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

## Example

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

// Declaration of the Mojo function
extern void hello(const char *msg);

// .Call wrapper for hello 
SEXP hello_call(SEXP msg) {

    if (!isString(msg) || LENGTH(msg) != 1)
        Rf_error("msg must be a single string");

    const char *cmsg = CHAR(STRING_ELT(msg, 0));
    hello(cmsg);

    return R_NilValue;
}
extern double add(double a, double b);
// .Call wrapper for the Mojo add function
SEXP add_call(SEXP a, SEXP b) {
    double ad = asReal(a);
    double bd = asReal(b);
    double result = add(ad, bd);
    return ScalarReal(result);
}

// Declaration of the Mojo convolution function
extern void convolve(const double *signal, int signal_len,
        const double *kernel, int kernel_len, double *output);
// .Call wrapper for the Mojo convolution function
SEXP convolve_call(SEXP signal, SEXP kernel) {
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
#> [1] -0.5259435 -0.1107400  0.2996034  0.6329625  0.6389078  0.2968331
# Benchmark
bench::mark(
        mojo = hellomojo::hellomojo_convolve(signal, kernel),
        c = c_convolve(signal, kernel),
        check = FALSE
)    
#> # A tibble: 2 × 6
#>   expression      min   median `itr/sec` mem_alloc `gc/sec`
#>   <bch:expr> <bch:tm> <bch:tm>     <dbl> <bch:byt>    <dbl>
#> 1 mojo        10.56µs   24.4µs    40674.    78.2KB     57.0
#> 2 c            9.98µs   32.9µs    32084.    78.2KB     45.0
```

## Limitations to investigate

Of course here we are using pixi to get Mojo binaries, installing this
on the R windows toolchain is not given. We should use uv or make a R
package that install pix. Moreover i could not add windown to the
current pixi workspace. This package should work fine on unix. We are
calling the mojo shared object in the same address space as R and
calling R C API from mojo ffi even though the toolchains were different.

Additionally we have an additional C wrapping which may be not required
if we pass the data directly to the mojo C callables.

Final issue that the pixi strategy download the whole mojo runtime and
toolchain (this amount to basically install llvm), leading a 1 GB
install !

## References

- [Mojo Getting Started
  Guide](https://docs.modular.com/mojo/manual/get-started)  
- [pixi: Package and Environment Manager](https://pixi.sh/)
- [simpleCall example](https://github.com/coolbutuseless/simpleCall)
