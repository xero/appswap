import ApplicationServices
import AppSwapCore
import Foundation
import MachO
import ServiceManagement

/// What the bundle says about this build.
struct Build {
	let bundleID, version, number, git: String?

	static let current: Build = {
		let info = Bundle.main.infoDictionary ?? [:]
		return Build(bundleID: Bundle.main.bundleIdentifier, version: info["CFBundleShortVersionString"] as? String,
			number: info["CFBundleVersion"] as? String, git: info["AppSwapGitHash"] as? String)
	}()

	/// The SDK version the linker wrote into this executable. AppKit picks its control styles from it.
	static var linkedSDK: UInt32? {
		guard let header = _dyld_get_image_header(0) else { return nil }
		var p = UnsafeRawPointer(header) + MemoryLayout<mach_header_64>.size
		for _ in 0..<header.pointee.ncmds {
			let lc = p.loadUnaligned(as: load_command.self)
			if lc.cmd == UInt32(LC_BUILD_VERSION) { return p.loadUnaligned(as: build_version_command.self).sdk }
			p += Int(lc.cmdsize)
		}
		return nil
	}
}

enum SelfTest {
	static func run() -> Bool {
		let b = Build.current, sdk = Build.linkedSDK
		#if DEBUG
		let config = "debug"
		#else
		let config = "release"
		#endif
		print("version=\(b.version ?? "nil") build=\(b.number ?? "nil") git=\(b.git ?? "nil") config=\(config)")
		print("bundle=\(b.bundleID ?? "nil")")
		print("sdk=\(sdk.map(versionString(packed:)) ?? "nil")")
		print("os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
		print("trusted=\(AXIsProcessTrusted())")
		for name in Private.names { print("private \(name)=\(Private.address(name) == nil ? "missing" : "found")") }
		return b.bundleID != nil && b.version != nil && sdk != nil
	}

	static func prompt() -> Bool {
		// The key is spelled out because the SDK's constant is a mutable global, which Swift 6 won't read here.
		let trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
		print("trusted=\(trusted)")
		return true
	}

	static func login(_ action: Mode.Login) -> Bool {
		let service = SMAppService.mainApp
		var ok = true
		do {
			switch action {
			case .on: try service.register()
			case .off: try service.unregister()
			case .status: break
			}
		} catch {
			let e = error as NSError
			print("error=\(e.domain) \(e.code) \(e.localizedDescription)")
			ok = false
		}
		let names = [SMAppService.Status.notRegistered: "notRegistered", .enabled: "enabled", .requiresApproval: "requiresApproval", .notFound: "notFound"]
		print("status=\(names[service.status] ?? "unknown(\(service.status.rawValue))")")
		return ok
	}
}
