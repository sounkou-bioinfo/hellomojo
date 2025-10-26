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
