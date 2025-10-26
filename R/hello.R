#' Call the native 'hello' function from the Mojo shared library
#'
#' @export
hellomojo <- function() {
    .Call(hello)
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
    .Call(convolve, as.numeric(signal), as.numeric(kernel))
}
