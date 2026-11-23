// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "appswap",
	platforms: [.macOS(.v15)],
	targets: [
		// Pure logic with no AppKit, so tests cover all of it.
		.target(name: "AppSwapCore"),
		.executableTarget(
			name: "appswap",
			dependencies: ["AppSwapCore"],
			swiftSettings: [.defaultIsolation(MainActor.self)]
		),
		.testTarget(name: "AppSwapCoreTests", dependencies: ["AppSwapCore"]),
		.testTarget(name: "appswapTests", dependencies: ["appswap"]),
	]
)
