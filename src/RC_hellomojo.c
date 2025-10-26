#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
// Declaration of the Mojo function
extern void hello();
extern double add(double a, double b);
// .Call wrapper for the Mojo add function
SEXP add_call(SEXP a, SEXP b) {
    double ad = asReal(a);
    double bd = asReal(b);
    double result = add(ad, bd);
    return ScalarReal(result);
}
// .Call wrapper for hello 
SEXP hello_call() {
    hello();
    return R_NilValue;
}
static const R_CallMethodDef CallEntries[] = {
    {"hello", (DL_FUNC) &hello_call, 0},
    {"add", (DL_FUNC) &add_call, 2},
    {NULL, NULL, 0}
};
void R_init_hellomojo(DllInfo *dll) {
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, TRUE);
    R_forceSymbols(dll, TRUE);
}
