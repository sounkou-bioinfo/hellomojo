
# hellomojo

An Example R Package that Uses ‘mojo’ Through the `.C` Interface

## Overview

This package provides a setup to call
[Mojo](https://www.modular.com/mojo) code from R using the mojo shared
library build mode. This was obviously designed for python interop. If
we only use simple types, we should easily call mojo using the `.C`
interface Some boilerplate is required, but this can be automated.

## How It Works ?

Mojo code is compile to shared libary, in our case `libhello.so`. A C
file [`RC_hellomojo.c`](src/RC_hellomojo.c) provides wrappers and
registration so R can call the Mojo functions via the `.C` interface. R
functions like `hellomojo()` call the native code using `.C()`. The
[`configure`](configure) script uses [pixi](https://pixi.sh/) to install
mojo and run the shared libary build.

## Example

``` r
# Load the package and call the native function
hellomojo::hellomojo()
#> list()
hellomojo::hellomojo_add(10,30)
#> [1] 40
```

the mojo code

``` bash
cat inst/mojo/hellomojo/hellomojo.mojo
# Mojo code for hello world and addition functions
# exported to c 

@export
fn hello():
    print("Hello, World!")

@export
fn add( a: Float64, b: Float64) -> Float64:
    print("a", a, "b", b)
    return a + b
```

the C wrappers

``` bash
cat  src/RC_hellomojo.c
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
// Declaration of the Mojo function
extern void hello();
extern double add( double a, double b);
// c wrapper for the Mojo add function
// we do this because we have no clue
// how to pass pointers to mojo functions
void add_(double *a, double *b, double *c) {
    *c = add(*a, *b);
}

static const R_CMethodDef CEntries[] = {
    {"hello", (DL_FUNC) &hello, 0},
    {"add", (DL_FUNC) &add_, 3},
    {NULL, NULL, 0}
};
void R_init_hellomojo(DllInfo *dll) {
    R_registerRoutines(dll, CEntries, NULL, NULL, NULL);
    R_useDynamicSymbols(dll, TRUE);
    R_forceSymbols(dll, TRUE);
}
```

## Limitations to investigate

Of course here we are using pixi to get Mojo binaries, installing this
on the R windows toolchain is not given. This package should work fine
on unix. Moreover we are calling the mojo shared object in the same
adress space as R even though the toolchains were different.

Additionally we have an additional C wrapping which may be not required
if we pass the data directly to the mojo C callables. Moreover we are
using the `.C` interface, which involves a lot of
[copies](https://github.com/coolbutuseless/simplec).

## References

[Mojo Getting Started
Guide](https://docs.modular.com/mojo/manual/get-started)  
[pixi: Package and Environment Manager](https://pixi.sh/) \[simpleC :\]
(<https://github.com/coolbutuseless/simplec>)
