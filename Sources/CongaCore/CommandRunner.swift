import Foundation

public protocol CommandRunning {
    func run(_ command: String)
}

/// Runs commands with `/bin/sh -c`, without waiting for them to finish.
public struct ShellCommandRunner: CommandRunning {
    public var environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func run(_ command: String) {
        run(command, completion: nil)
    }

    /// `completion` receives the exit status, or -1 if the shell could not be launched.
    ///
    /// Stdin is a pseudo-terminal, as it would be for a command typed into a terminal. Some
    /// tools (AeroSpace 0.20+ among them) refuse to run when stdin is a file or pipe.
    public func run(_ command: String, completion: (@Sendable (Int32) -> Void)?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        var primary: Int32 = -1
        var replica: Int32 = -1
        let terminal: FileHandle?
        if openpty(&primary, &replica, nil, nil, nil) == 0 {
            terminal = FileHandle(fileDescriptor: primary, closeOnDealloc: true)
            process.standardInput = FileHandle(fileDescriptor: replica, closeOnDealloc: true)
        } else {
            terminal = nil
            process.standardInput = FileHandle.nullDevice
        }

        process.terminationHandler = { process in
            // Keep our end of the terminal open until the command is done.
            try? terminal?.close()
            completion?(process.terminationStatus)
        }
        do {
            try process.run()
        } catch {
            try? terminal?.close()
            completion?(-1)
        }
    }

    /// The current environment with `PATH` taken from the user's login shell.
    ///
    /// Apps launched from Finder get a minimal `PATH` that lacks Homebrew and friends. Asking
    /// the login shell once at startup is much cheaper than starting one per command.
    public static func loginShellEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        let fallback = ["/opt/homebrew/bin", "/usr/local/bin", base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]
            .joined(separator: ":")
        environment["PATH"] = loginShellPath(shell: base["SHELL"] ?? "/bin/zsh") ?? fallback
        return environment
    }

    static func loginShellPath(shell: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: shell)
        // printenv rather than `echo $PATH`: fish prints list variables space-separated.
        process.arguments = ["-l", "-c", "printenv PATH"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        // Shell startup files may print their own output first; PATH is the last line.
        let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
        guard let path = lines.last, path.contains("/") else { return nil }
        return String(path)
    }
}
