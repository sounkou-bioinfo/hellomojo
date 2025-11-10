# Mojo code for hello world and addition functions
# exported to c
# load necessary FFI types for accessing R C API functions
# since we are in the same adress space as R when calling these functions
from sys.ffi import c_char, c_int
from sys.ffi import external_call
from memory.unsafe_pointer import UnsafePointer
from sys import CompilationTarget, num_logical_cores, num_physical_cores

# Rprintf type: takes a C string pointer, returns int
alias Rprintf_type = fn(UnsafePointer[c_char]) -> c_int

@export
fn hello(msg: UnsafePointer[c_char]):
    # Use external_call to call Rprintf directly
    _ = external_call["Rprintf", c_int](msg)

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

@export
fn device_info(device_id: Int32, api_name: UnsafePointer[c_char]):
    # Always show CPU information first
    _ = external_call["Rprintf", c_int]("=== System Information ===\n".unsafe_ptr())
    
    # Simple OS detection
    var os_name = "unix"
    if CompilationTarget.is_linux():
        os_name = "linux"
    elif CompilationTarget.is_macos():
        os_name = "macOS"
        
    # Get CPU architecture 
    var cpu_arch = CompilationTarget._arch()
    
    # Determine CPU features
    var cpu_features = String()
    if CompilationTarget.has_sse4():
        cpu_features += " sse4"
    if CompilationTarget.has_avx():
        cpu_features += " avx"
    if CompilationTarget.has_avx2():
        cpu_features += " avx2"
    if CompilationTarget.has_avx512f():
        cpu_features += " avx512f"
    if CompilationTarget.has_neon():
        cpu_features += " neon"
    if CompilationTarget.is_apple_silicon():
        cpu_features += " apple_silicon"
    
    # Print CPU information
    _ = external_call["Rprintf", c_int]("CPU Information:\n".unsafe_ptr())
    var os_msg = "  OS             : " + os_name + "\n"
    _ = external_call["Rprintf", c_int](os_msg.unsafe_ptr())
    var cpu_msg = "  CPU Arch       : " + String(cpu_arch) + "\n"
    _ = external_call["Rprintf", c_int](cpu_msg.unsafe_ptr())
    var phys_cores_msg = "  Physical Cores : " + String(num_physical_cores()) + "\n"
    _ = external_call["Rprintf", c_int](phys_cores_msg.unsafe_ptr())
    var log_cores_msg = "  Logical Cores  : " + String(num_logical_cores()) + "\n"
    _ = external_call["Rprintf", c_int](log_cores_msg.unsafe_ptr())
    var features_msg = "  CPU Features   :" + cpu_features + "\n"
    _ = external_call["Rprintf", c_int](features_msg.unsafe_ptr())
    
    # GPU status message
    _ = external_call["Rprintf", c_int]("\nGPU Information:\n".unsafe_ptr())
    _ = external_call["Rprintf", c_int]("  Status         : GPU detection requires additional Mojo modules\n".unsafe_ptr())
