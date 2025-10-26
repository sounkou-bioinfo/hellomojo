#' Call the native 'hello' function from the Mojo shared library
#'
#' @export
hellomojo <- function() {
    .C(hello)
}
