.has_mojo <- function() {
    lib_path <- system.file("libs", package = "hellomojo")
    if (lib_path == "") {
        return(FALSE)
    }

    libsuffix <- if (Sys.info()["sysname"] == "Darwin") "dylib" else "so"
    file.exists(file.path(lib_path, paste0("libhello.", libsuffix)))
}

#' Call the native 'hello' function from the Mojo shared library
#'
#' @export
hellomojo <- function() {
    invisible(.Call(hello, "hello from R via Mojo!"))
}

#' Add two numbers using the native 'add' function from the Mojo shared library
#' @param a A numeric value
#' @param b A numeric value
#' @return The sum of a and b
#' @export
hellomojo_add <- function(a, b) {
    .Call(add, as.numeric(a), as.numeric(b))
}

#' 1D convolution using the native Mojo function
#' @param signal Numeric vector (signal)
#' @param kernel Numeric vector (kernel)
#' @return Numeric vector (convolution result)
#' @export
hellomojo_convolve <- function(signal, kernel) {
    if (!.has_mojo()) {
        # R fallback
        signal <- as.numeric(signal)
        kernel <- as.numeric(kernel)
        n_out <- length(signal) - length(kernel) + 1
        vapply(seq_len(n_out), function(i) {
            sum(signal[i:(i + length(kernel) - 1)] * kernel)
        }, numeric(1))
    } else {
        .Call(convolve, as.numeric(signal), as.numeric(kernel))
    }
}
