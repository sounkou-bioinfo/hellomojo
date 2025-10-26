# Mojo code for hello world and addition functions
# exported to c 

@export
fn hello():
    print("Hello, World!")

@export
fn add( a: Float64, b: Float64) -> Float64:
    return a + b

@export
fn convolve(signal: UnsafePointer[Float64], signal_len: Int, kernel: UnsafePointer[Float64], kernel_len: Int, output: UnsafePointer[Float64]):
    i: Int = 0
    while i < signal_len - kernel_len + 1:
        acc: Float64 = 0.0
        j: Int = 0
        while j < kernel_len:
            acc = acc + (signal + i + j)[] * (kernel + j)[]
            j = j + 1
        (output + i)[] = acc
        i = i + 1
