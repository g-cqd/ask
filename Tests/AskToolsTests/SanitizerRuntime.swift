import Darwin

/// Whether this test process runs under a sanitizer. An exit test's child cannot start then: on macOS it aborts at once, whatever its
/// body (seen with the address and thread sanitizers, Swift 6.4), so such a test is skipped there and run everywhere else.
enum SanitizerRuntime {
    static let isLoaded: Bool = {
        // RTLD_DEFAULT: every image loaded in the process.
        let everywhere = UnsafeMutableRawPointer(bitPattern: -2)
        for name in ["__asan_init", "__tsan_init", "__ubsan_handle_builtin_unreachable"]
        where unsafe dlsym(everywhere, name) != nil {
            return true
        }
        return false
    }()
}
