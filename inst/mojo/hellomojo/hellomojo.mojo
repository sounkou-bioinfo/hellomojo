# Mojo code for hello world and addition functions
# exported to c 

@export
fn hello():
    print("Hello, World!")

@export
fn add( a: Float64, b: Float64) -> Float64:
    print("a", a, "b", b)
    return a + b
