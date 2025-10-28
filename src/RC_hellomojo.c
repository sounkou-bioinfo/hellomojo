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
