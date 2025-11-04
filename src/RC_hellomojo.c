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
