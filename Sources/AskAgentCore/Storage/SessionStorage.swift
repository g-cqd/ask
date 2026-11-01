/// How a ``SessionFile`` keeps its file, handed to it when it is made: the format, the keys, and for a framed file the writer that
/// continues it.
struct SessionStorage: ~Copyable {
    var format: SessionFormat = .plain
    var keyring: SessionKeyring?
    var fileKey: FileKey?
    var framer: FramedWriter?
}
