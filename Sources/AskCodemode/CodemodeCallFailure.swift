/// Why a call a script made did not return: the tool's own words, which the script gets as an `Error`'s message.
package struct CodemodeCallFailure: Error, Sendable, Equatable {
    package let message: String

    package init(_ message: String) { self.message = message }
}
