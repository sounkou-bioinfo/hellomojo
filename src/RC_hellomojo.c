#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
// Declaration of the Mojo function
extern void hello();
static const R_CMethodDef CEntries[] = {
    {"hello", (DL_FUNC) &hello, 0},
    {NULL, NULL, 0}
};
void R_init_hellomojo(DllInfo *dll) {
    R_registerRoutines(dll, CEntries, NULL, NULL, NULL);
    R_useDynamicSymbols(dll, TRUE);
    R_forceSymbols(dll, TRUE);
}
