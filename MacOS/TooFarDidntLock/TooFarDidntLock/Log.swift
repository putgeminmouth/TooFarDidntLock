import OSLog

struct Log {
    static func Logger(_ category: String) -> Logger {
        return os.Logger(subsystem: "TooFarDidntLock", category: category)
    }
}
