/// What one launch does, decided by its first argument.
public enum Mode: Equatable, Sendable {
	case run
	case selftest
	case prompt
	case login(Login)
	case axprobe(wait: Int, titles: Bool)
	case usage(String)

	public enum Login: String, Sendable { case on, off, status }

	public init(_ args: [String]) {
		// Only a leading "--" names a mode, so a stray argument from the launcher still starts the app.
		guard let first = args.first, first.hasPrefix("--") else { self = .run; return }
		let rest = Array(args.dropFirst())
		switch first {
		case "--selftest": self = .selftest
		case "--prompt": self = .prompt
		case "--login":
			self = rest.first.flatMap(Login.init).map(Mode.login) ?? .usage("--login takes on, off, or status")
		case "--axprobe":
			var wait = 0, titles = false, i = 0
			while i < rest.count {
				switch rest[i] {
				case "--titles": titles = true
				case "--wait":
					i += 1
					guard i < rest.count, let n = Int(rest[i]), n >= 0 else { self = .usage("--wait takes a number of seconds"); return }
					wait = n
				default: self = .usage("unknown --axprobe option \(rest[i])"); return
				}
				i += 1
			}
			self = .axprobe(wait: wait, titles: titles)
		default: self = .usage("unknown mode \(first)")
		}
	}
}

/// Renders a Mach-O packed version (major in the high 16 bits, then minor and patch bytes).
public func versionString(packed v: UInt32) -> String {
	let (major, minor, patch) = (v >> 16, (v >> 8) & 0xff, v & 0xff)
	return patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
}
