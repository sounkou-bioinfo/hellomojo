#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <stdio.h>
#include <stdlib.h>
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
    char tmpname[L_tmpnam];
    tmpnam(tmpname);
    FILE *tmp = freopen(tmpname, "w+", stdout);
    if (!tmp) {
        error("Failed to redirect stdout");
    }
    hello();
    fflush(stdout);
    freopen("/dev/tty", "w", stdout); // restore stdout
    fseek(tmp, 0, SEEK_SET);
    char buffer[4096];
    size_t n = fread(buffer, 1, sizeof(buffer) - 1, tmp);
    buffer[n] = '\0';
    fclose(tmp);
    return Rf_mkString(buffer);
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
