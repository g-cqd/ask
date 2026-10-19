import AskAgentCore
import Benchmark
import Foundation

// What starting ask pays to read its configuration (roadmap 0038, ADR-0031): the user's file, a trusted
// project file with its SHA-256 check and the trust store, and the environment; and, for reload, the same
// again before every prompt. With no files at all, which is most first runs.
func configurationBenchmarks() {
    func directory() throws -> (config: String, project: String) {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-bench-config-\(UUID().uuidString)")
        let config = root.appending(path: "config").path
        let project = root.appending(path: "project").path
        try FileManager.default.createDirectory(atPath: config, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: project + "/.ask", withIntermediateDirectories: true)
        return (config, project)
    }

    Benchmark("config/load with no files") { benchmark in
        let (config, project) = try directory()
        let loader = ConfigurationLoader(project: project, configDirectory: config, environment: [:])
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations { blackHole(try loader.load()) }
        benchmark.stopMeasurement()
    }

    Benchmark("config/load user file, trusted project file, environment") { benchmark in
        let (config, project) = try directory()
        let user = "// settings\n{model: 'claude-sonnet-5-5', maxTurns: 40, compactAt: 120000,}\n"
        let projectText = "{maxTurns: 20, compactAt: 90000}"
        try Data(user.utf8).write(to: URL(filePath: config + "/config.json"))
        try Data(projectText.utf8).write(to: URL(filePath: project + "/.ask/config.json"))
        var trust = ProjectTrust()
        trust.trust(project + "/.ask/config.json", bytes: Array(projectText.utf8))
        try trust.save(to: config + "/trusted.json")
        let loader = ConfigurationLoader(
            project: project, configDirectory: config, environment: ["ASK_MAX_TURNS": "30", "PATH": "/usr/bin"])
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations { blackHole(try loader.load(maxTurns: 10)) }
        benchmark.stopMeasurement()
    }
}
