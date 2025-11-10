#' Hello from Mojo
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
  .Call(convolve, as.numeric(signal), as.numeric(kernel))
}

#' Get system and GPU device information using Mojo
#' Shows both CPU and GPU information when available
#' @param device_id Integer device ID (default: 0)
#' @param api_name Character string specifying the GPU API ("cuda" or "hip", default: "cuda")
#' @return Prints system and device information to console
#' @export
hellomojo_device_info <- function(device_id = 0L, api_name = "cuda") {
  invisible(.Call(device_info, as.integer(device_id), as.character(api_name)))
}
