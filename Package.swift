// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AgentTrafficLights",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentTrafficLights", targets: ["AgentTrafficLights"]),
        .executable(name: "AgentStatusCollector", targets: ["AgentStatusCollector"]),
        .executable(name: "AgentClaudeHook", targets: ["AgentClaudeHook"]),
        .library(name: "AgentTrafficLightsCore", targets: ["AgentTrafficLightsCore"])
    ],
    targets: [
        .target(name: "AgentTrafficLightsCore", path: "Sources/AgentTrafficLightsCore"),
        .executableTarget(
            name: "AgentTrafficLights",
            dependencies: ["AgentTrafficLightsCore"],
            path: "Sources/AgentTrafficLights"
        ),
        .executableTarget(
            name: "AgentStatusCollector",
            dependencies: ["AgentTrafficLightsCore"],
            path: "Sources/AgentStatusCollector"
        ),
        .executableTarget(
            name: "AgentClaudeHook",
            dependencies: ["AgentTrafficLightsCore"],
            path: "Sources/AgentClaudeHook"
        ),
        .testTarget(
            name: "AgentTrafficLightsCoreTests",
            dependencies: ["AgentTrafficLightsCore"],
            path: "Tests/AgentTrafficLightsCoreTests"
        ),
        .testTarget(
            name: "AgentStatusCollectorTests",
            dependencies: ["AgentStatusCollector", "AgentTrafficLightsCore"],
            path: "Tests/AgentStatusCollectorTests"
        ),
        .testTarget(
            name: "AgentTrafficLightsTests",
            dependencies: ["AgentTrafficLights", "AgentTrafficLightsCore"],
            path: "Tests/AgentTrafficLightsTests"
        )
    ]
)
