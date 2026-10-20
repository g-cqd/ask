/// The deny-default base a restricted-read profile starts from (roadmap 0042): what any process needs to start, find
/// its user, log, trust a certificate, use a terminal and read the system. Everything else is denied, then the
/// policy's own allowances and protections follow.
///
/// Written by probing, with Codex 0.163.0's base profile as a catalogue (diary 42): SwiftPM, git, Python, curl, cc,
/// make and rg run under it. Each group says why it is here.
enum SeatbeltBase {
    static let lines: [String] =
        [
            "(deny default)",
            // Child processes inherit the profile; signals and process information stay within it.
            "(allow process-exec process-fork)",
            "(allow signal (target same-sandbox))",
            "(allow process-info* (target same-sandbox))",
            // The sysctls runtimes read at start: CPU, memory, OS version, limits. Listed, not all.
            "(allow sysctl-read "
                + sysctls.map { "(\($0.prefix ? "sysctl-name-prefix" : "sysctl-name") \"\($0.name)\")" }
                .joined(separator: " ") + ")",
            // User and group lookup, logging, notifications, certificate trust, preferences, the per-user temp
            // directory (without dirhelper, clang falls back to ~/.cache and fails).
            "(allow mach-lookup (global-name " + machServices.map { "\"\($0)\"" }.joined(separator: " ") + "))",
            "(allow ipc-posix-shm-read* (ipc-posix-name-prefix \"apple.cfprefs.\") (ipc-posix-name \"apple.shm.notification_center\"))",
            "(allow ipc-posix-sem)",
            "(allow user-preference-read)",
            "(allow system-mac-syscall (mac-policy-name \"vnguard\"))",
            "(allow system-mac-syscall (require-all (mac-policy-name \"Sandbox\") (mac-syscall-number 67)))",
            "(allow network-outbound (literal \"/private/var/run/syslog\"))",
            // Terminals and the standard devices.
            "(allow pseudo-tty)",
            "(allow file-read* file-write* file-ioctl (literal \"/dev/null\") (literal \"/dev/zero\") (literal \"/dev/tty\") "
                + "(literal \"/dev/ptmx\") (literal \"/dev/dtracehelper\") (regex #\"^/dev/ttys[0-9]+$\") (subpath \"/dev/fd\"))",
            // Metadata everywhere, so paths resolve and the working directory is found; contents only below.
            "(allow file-read-metadata)",
            "(allow file-read* (literal \"/\"))",
            "(allow file-read* " + SandboxPolicy.systemReadRoots.map { "(subpath \"\($0)\")" }.joined(separator: " ")
                + ")"
        ]

    /// Mach services a process needs to start, find its user, log, trust a certificate and read preferences.
    private static let machServices = names(
        """
        com.apple.system.opendirectoryd.libinfo com.apple.system.opendirectoryd.membership
        com.apple.system.DirectoryService.libinfo_v1 com.apple.bsd.dirhelper com.apple.logd com.apple.logd.events
        com.apple.system.logger com.apple.diagnosticd com.apple.system.notification_center com.apple.trustd
        com.apple.trustd.agent com.apple.secinitd com.apple.cfprefsd.daemon com.apple.cfprefsd.agent
        com.apple.analyticsd com.apple.espd
        """)

    /// The sysctls runtimes read, by exact name, then by prefix.
    private static let sysctls: [(name: String, prefix: Bool)] =
        names(
            """
            hw.activecpu hw.busfrequency_compat hw.byteorder hw.cacheconfig hw.cachelinesize_compat hw.cpufamily
            hw.cpufrequency hw.cpufrequency_compat hw.cputype hw.l1dcachesize_compat hw.l1icachesize_compat
            hw.l2cachesize_compat hw.l3cachesize_compat hw.logicalcpu hw.logicalcpu_max hw.machine hw.memsize hw.model
            hw.ncpu hw.nperflevels hw.packages hw.pagesize hw.pagesize_compat hw.physicalcpu hw.physicalcpu_max
            hw.tbfrequency_compat hw.vectorunit kern.argmax kern.hostname kern.maxfilesperproc kern.maxproc
            kern.osproductversion kern.osrelease kern.ostype kern.osvariant_status kern.osversion kern.secure_kernel
            kern.sysv.semmns kern.usrstack64 kern.version machdep.cpu.brand_string sysctl.proc_cputype vm.loadavg
            """
        )
        .map { ($0, false) }
        + names("hw.optional.arm. hw.optional.armv8_ hw.perflevel kern.proc.pgrp. kern.proc.pid. net.routetable.")
        .map { ($0, true) }

    /// Whitespace-separated names, as a list.
    private static func names(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
