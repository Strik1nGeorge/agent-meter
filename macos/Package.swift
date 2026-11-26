// swift-tools-version:5.9
import PackageDescription

// The macOS widget: AgentMeterCore holds the logic shared in meaning with the Windows widget (rings, pace,
// card texts, placement) and is unit-tested; AgentMeter is the app that draws it. Build the app bundle
// with build.sh.
let package = Package(
    name: "AgentMeter",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AgentMeter", targets: ["AgentMeter"])],
    targets: [
        .target(name: "AgentMeterCore", path: "Sources/AgentMeterCore"),
        .executableTarget(name: "AgentMeter", dependencies: ["AgentMeterCore"], path: "Sources/AgentMeter"),
        .testTarget(name: "AgentMeterCoreTests", dependencies: ["AgentMeterCore"], path: "Tests/AgentMeterCoreTests"),
    ]
)
