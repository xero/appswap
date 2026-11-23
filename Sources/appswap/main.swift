import AppKit
import AppSwapCore
import os

// Output goes to a file through `open --stdout`, and line buffering keeps it whole if a mode crashes.
setvbuf(stdout, nil, _IOLBF, 0)

/// Ends a command-line mode. `open` reports its own status, so callers read this last line instead.
func finish(_ ok: Bool) -> Never {
	print(ok ? "ok" : "failed")
	exit(ok ? 0 : 1)
}

// Every mode exits here, before the app claims anything a running copy holds.
switch Mode(Array(CommandLine.arguments.dropFirst())) {
case .selftest: finish(SelfTest.run())
case .prompt: finish(SelfTest.prompt())
case .login(let action): finish(SelfTest.login(action))
case .axprobe(let wait, let titles): finish(Probe.run(wait: wait, titles: titles))
case .usage(let why): print(why); finish(false)
case .run: break
}

let build = Build.current
let bundleID = build.bundleID ?? "style.xero.appswap.unbundled"
let log = Logger(subsystem: bundleID, category: "app")
log.notice("launch version=\(build.version ?? "nil", privacy: .public) build=\(build.number ?? "nil", privacy: .public) git=\(build.git ?? "nil", privacy: .public)")

if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { $0.processIdentifier != getpid() }) {
	log.notice("another copy is running, exiting")
	exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.run()
