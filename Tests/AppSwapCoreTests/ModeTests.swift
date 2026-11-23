import Testing
@testable import AppSwapCore

@Suite struct ModeTests {
	@Test func noArgumentsRunTheApp() {
		#expect(Mode([]) == .run)
		#expect(Mode(["stray"]) == .run)
	}

	@Test func namedModes() {
		#expect(Mode(["--selftest"]) == .selftest)
		#expect(Mode(["--prompt"]) == .prompt)
		#expect(Mode(["--login", "on"]) == .login(.on))
		#expect(Mode(["--login", "off"]) == .login(.off))
		#expect(Mode(["--login", "status"]) == .login(.status))
		#expect(Mode(["--axprobe"]) == .axprobe(wait: 0, titles: false))
		#expect(Mode(["--axprobe", "--wait", "15", "--titles"]) == .axprobe(wait: 15, titles: true))
	}

	@Test(arguments: [["--login"], ["--login", "maybe"], ["--axprobe", "--wait"], ["--axprobe", "--wait", "x"], ["--axprobe", "--wait", "-1"], ["--axprobe", "--nope"], ["--nope"]])
	func badArgumentsAreUsage(args: [String]) {
		guard case .usage = Mode(args) else { Issue.record("\(args) parsed as \(Mode(args))"); return }
	}

	@Test func packedVersions() {
		#expect(versionString(packed: 0x001B_0000) == "27.0")
		#expect(versionString(packed: 0x000F_0000) == "15.0")
		#expect(versionString(packed: 0x001B_0201) == "27.2.1")
	}
}
