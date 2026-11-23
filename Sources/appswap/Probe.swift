import AppKit
import ApplicationServices

/// A read-only report of what the WindowServer and Accessibility say about every regular app.
/// It runs once and exits, so its Accessibility reads have no run loop to stall and stay on the main thread.
enum Probe {
	static func run(wait: Int, titles: Bool) -> Bool {
		let trusted = AXIsProcessTrusted()
		let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
		let finder = apps.first { $0.bundleIdentifier == "com.apple.finder" }
		let ordered = (finder.map { [$0] } ?? []) + apps.filter { $0 != finder }
		print("os=\(ProcessInfo.processInfo.operatingSystemVersionString) trusted=\(trusted) apps=\(apps.count) frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil")")

		let ws = WS()
		if ws == nil { print("windowserver: a private symbol is missing, no rows") }
		ws?.report(ordered)
		guard trusted else {
			print("not trusted, so no Accessibility call was made")
			return false
		}

		// The design's timeout, so one hung app costs a quarter second and not the default six.
		AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
		let cg = cgWindows()
		var held: [(wid: CGWindowID?, el: AXUIElement)] = []
		print("\n== accessibility, first contact ==")
		var t = now()
		for app in ordered {
			let isFinder = app == finder
			let wins = report(app, cg: cg, ws: ws, titles: titles || isFinder)
			if isFinder { held = wins }
		}
		print("first pass total ms=\(ms(t))")
		t = now()
		for app in ordered { _ = windows(of: app) }
		print("second pass, app reads only, total ms=\(ms(t))")
		if let finder { children(of: finder) }

		if wait > 0 {
			print("\n== holding \(held.count) Finder elements for \(wait) s, put an app in native fullscreen now ==")
			sleep(UInt32(wait))
			print("frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil")")
			ws?.report(finder.map { [$0] } ?? [])
			for (i, h) in held.enumerated() {
				let r = read(h.el, winAttrs)
				print("held[\(i)] wid then=\(str(h.wid)) now=\(str(windowID(h.el))) \(describe(r, titles: true))")
			}
			if let finder {
				let w = windows(of: finder)
				print("fresh Finder read: err=\(name(w.err)) windows=\(w.all.map { str(windowID($0)) }) main=\(str(w.main.flatMap(windowID))) focused=\(str(w.focused.flatMap(windowID)))")
			}
		}
		return true
	}

	// MARK: Accessibility

	// An app element is asked for these three and nothing else, because asking for its role
	// switches on Chromium's accessibility engine.
	static let appAttrs = [kAXWindowsAttribute, kAXMainWindowAttribute, kAXFocusedWindowAttribute]
	static let winAttrs = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute, kAXPositionAttribute,
		kAXSizeAttribute, kAXMainAttribute, kAXFocusedAttribute, "AXFullScreen", kAXModalAttribute]

	typealias Read = (err: AXError, v: [AnyObject?], ms: String)

	/// Several attributes in one round trip. A slot is nil when the app had no value for it.
	static func read(_ el: AXUIElement, _ attrs: [String]) -> Read {
		var out: CFArray?
		let t = now()
		let e = AXUIElementCopyMultipleAttributeValues(el, attrs as CFArray, [], &out)
		let took = ms(t)
		let none = [AnyObject?](repeating: nil, count: attrs.count)
		guard e == .success, let arr = out as? [AnyObject] else { return (e, none, took) }
		let vals: [AnyObject?] = arr.map { v in
			v is NSNull || (CFGetTypeID(v) == AXValueGetTypeID() && AXValueGetType(v as! AXValue) == .axError) ? nil : v
		}
		return (e, Array((vals + none).prefix(attrs.count)), took)
	}

	static func element(_ v: AnyObject?) -> AXUIElement? {
		guard let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
		return (v as! AXUIElement)
	}

	static func windows(of app: NSRunningApplication) -> (err: AXError, ms: String, listed: Int, all: [AXUIElement], main: AXUIElement?, focused: AXUIElement?) {
		let r = read(AXUIElementCreateApplication(app.processIdentifier), appAttrs)
		var all: [AXUIElement] = []
		// The list can repeat an element, and the main or focused window can be missing from it.
		for w in (r.v[0] as? [AnyObject] ?? []).compactMap(element) where !all.contains(where: { CFEqual($0, w) }) { all.append(w) }
		let listed = all.count, main = element(r.v[1]), focused = element(r.v[2])
		for w in [main, focused].compactMap({ $0 }) where !all.contains(where: { CFEqual($0, w) }) { all.append(w) }
		return (r.err, r.ms, listed, all, main, focused)
	}

	static let getWindow: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = Private.bind("_AXUIElementGetWindow")

	static func windowID(_ el: AXUIElement) -> CGWindowID? {
		var wid = CGWindowID(0)
		return getWindow?(el, &wid) == .success && wid != 0 ? wid : nil
	}

	static func describe(_ r: Read, titles: Bool) -> String {
		func val(_ i: Int) -> String { r.v[i].map { "\($0)" } ?? "nil" }
		var pos = CGPoint.zero, size = CGSize.zero
		let hasPos = r.v[4].map { AXValueGetValue($0 as! AXValue, .cgPoint, &pos) } ?? false
		let hasSize = r.v[5].map { AXValueGetValue($0 as! AXValue, .cgSize, &size) } ?? false
		let title = (r.v[2] as? String).map { titles ? "\"\($0)\"" : "len=\($0.count)" } ?? "nil"
		return "err=\(name(r.err)) ms=\(r.ms) role=\(val(0)) subrole=\(val(1)) title=\(title) minimized=\(val(3))"
			+ " pos=\(hasPos ? "\(Int(pos.x)),\(Int(pos.y))" : "nil") size=\(hasSize ? "\(Int(size.width))x\(Int(size.height))" : "nil")"
			+ " main=\(val(6)) focused=\(val(7)) fullscreen=\(val(8)) modal=\(val(9))"
	}

	/// Prints one app's windows and returns them with their window ids.
	static func report(_ app: NSRunningApplication, cg: [CGWindowID: (onscreen: Bool, z: Int?)], ws: WS?, titles: Bool) -> [(wid: CGWindowID?, el: AXUIElement)] {
		let w = windows(of: app)
		print("\nAPP \(app.bundleIdentifier ?? "nil") pid=\(app.processIdentifier) hidden=\(app.isHidden) active=\(app.isActive)")
		print("  app read: err=\(name(w.err)) ms=\(w.ms) listed=\(w.listed) total=\(w.all.count) main=\(w.main == nil ? "nil" : "element") focused=\(w.focused == nil ? "nil" : "element")")
		var out: [(wid: CGWindowID?, el: AXUIElement)] = []
		for (i, el) in w.all.enumerated() {
			let wid = windowID(el), c = wid.flatMap { cg[$0] }
			let flags = [i < w.listed ? "listed" : "unlisted", w.main.map { CFEqual($0, el) } == true ? "isMain" : nil, w.focused.map { CFEqual($0, el) } == true ? "isFocused" : nil].compactMap { $0 }
			print("  win[\(i)] wid=\(str(wid)) \(flags.joined(separator: ",")) \(describe(read(el, winAttrs), titles: titles)) cg[onscreen=\(str(c?.onscreen)) z=\(str(c?.z))]")
			out.append((wid, el))
		}
		// Shows whether the list comes back front to back.
		print("  on-screen z in Accessibility order: \(out.compactMap { $0.wid.flatMap { cg[$0]?.z } })")
		if let ws {
			let ax = Set(out.compactMap(\.wid)), rows = ws.candidates(app)
			print("  windowserver candidates Accessibility didn't return: \(rows.filter { !ax.contains($0.wid) }.map(\.wid))")
			print("  Accessibility windows that aren't candidates: \(ax.subtracting(rows.map(\.wid)).sorted())")
		}
		return out
	}

	/// Shows how Finder reports the desktop, which sits among its windows.
	static func children(of finder: NSRunningApplication) {
		var kids: CFTypeRef?
		let e = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(finder.processIdentifier), kAXChildrenAttribute as CFString, &kids)
		let els = (kids as? [AnyObject] ?? []).compactMap(element)
		print("\n== Finder children: err=\(name(e)) count=\(els.count) ==")
		for (i, k) in els.prefix(40).enumerated() {
			let r = read(k, [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXRoleDescriptionAttribute])
			print("  child[\(i)] wid=\(str(windowID(k))) role=\(str(r.v[0])) subrole=\(str(r.v[1])) title=\(str(r.v[2])) roleDescription=\(str(r.v[3]))")
		}
	}

	static func cgWindows() -> [CGWindowID: (onscreen: Bool, z: Int?)] {
		func list(_ o: CGWindowListOption) -> [CGWindowID] {
			(CGWindowListCopyWindowInfo(o, kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
		}
		let z = Dictionary(list([.optionOnScreenOnly, .excludeDesktopElements]).enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
		return Dictionary(list(.optionAll).map { ($0, (z[$0] != nil, z[$0])) }, uniquingKeysWith: { a, _ in a })
	}

	// MARK: Formatting

	static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
	static func ms(_ since: UInt64) -> String { String(format: "%.2f", Double(now() - since) / 1e6) }
	static func str<T>(_ v: T?) -> String { v.map { "\($0)" } ?? "nil" }

	static func name(_ e: AXError) -> String {
		let names: [AXError: String] = [.success: "success", .failure: "failure", .illegalArgument: "illegalArgument", .invalidUIElement: "invalidUIElement",
			.cannotComplete: "cannotComplete", .attributeUnsupported: "attributeUnsupported", .notImplemented: "notImplemented", .apiDisabled: "apiDisabled", .noValue: "noValue"]
		return names[e] ?? "AXError(\(e.rawValue))"
	}

	// MARK: WindowServer

	/// The private read-only queries that list every window on every Space. They need no grant.
	struct WS {
		let conn: @convention(c) () -> Int32
		let spaces: @convention(c) (Int32) -> Unmanaged<CFArray>?
		let list: @convention(c) (Int32, UInt32, CFArray, UInt32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>) -> Unmanaged<CFArray>?
		let query: @convention(c) (Int32, CFArray, Int32) -> Unmanaged<CFTypeRef>?
		let result: @convention(c) (UnsafeRawPointer) -> Unmanaged<CFTypeRef>?
		let advance: @convention(c) (UnsafeRawPointer) -> Bool
		let wid, parent: @convention(c) (UnsafeRawPointer) -> UInt32
		let pid, level: @convention(c) (UnsafeRawPointer) -> Int32
		let tags, attrs, mask: @convention(c) (UnsafeRawPointer) -> UInt64
		let alpha: @convention(c) (UnsafeRawPointer) -> Float
		let bounds: @convention(c) (UnsafeRawPointer) -> CGRect

		init?() {
			guard let conn: @convention(c) () -> Int32 = Private.bind("CGSMainConnectionID"),
				let spaces: @convention(c) (Int32) -> Unmanaged<CFArray>? = Private.bind("CGSCopyManagedDisplaySpaces"),
				let list: @convention(c) (Int32, UInt32, CFArray, UInt32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>) -> Unmanaged<CFArray>? = Private.bind("CGSCopyWindowsWithOptionsAndTags"),
				let query: @convention(c) (Int32, CFArray, Int32) -> Unmanaged<CFTypeRef>? = Private.bind("SLSWindowQueryWindows"),
				let result: @convention(c) (UnsafeRawPointer) -> Unmanaged<CFTypeRef>? = Private.bind("SLSWindowQueryResultCopyWindows"),
				let advance: @convention(c) (UnsafeRawPointer) -> Bool = Private.bind("SLSWindowIteratorAdvance"),
				let wid: @convention(c) (UnsafeRawPointer) -> UInt32 = Private.bind("SLSWindowIteratorGetWindowID"),
				let parent: @convention(c) (UnsafeRawPointer) -> UInt32 = Private.bind("SLSWindowIteratorGetParentID"),
				let pid: @convention(c) (UnsafeRawPointer) -> Int32 = Private.bind("SLSWindowIteratorGetPID"),
				let level: @convention(c) (UnsafeRawPointer) -> Int32 = Private.bind("SLSWindowIteratorGetLevel"),
				let tags: @convention(c) (UnsafeRawPointer) -> UInt64 = Private.bind("SLSWindowIteratorGetTags"),
				let attrs: @convention(c) (UnsafeRawPointer) -> UInt64 = Private.bind("SLSWindowIteratorGetAttributes"),
				let mask: @convention(c) (UnsafeRawPointer) -> UInt64 = Private.bind("SLSWindowIteratorGetSpaceTypeMask"),
				let alpha: @convention(c) (UnsafeRawPointer) -> Float = Private.bind("SLSWindowIteratorGetAlpha"),
				let bounds: @convention(c) (UnsafeRawPointer) -> CGRect = Private.bind("SLSWindowIteratorGetBounds")
			else { return nil }
			(self.conn, self.spaces, self.list, self.query, self.result, self.advance) = (conn, spaces, list, query, result, advance)
			(self.wid, self.parent, self.pid, self.level, self.tags, self.attrs, self.mask, self.alpha, self.bounds) = (wid, parent, pid, level, tags, attrs, mask, alpha, bounds)
		}

		struct Space { let id: UInt64, type: Int, display: Int, showing: Bool }

		struct Row {
			let wid: UInt32, pid: Int32, level: Int32, attrs, tags, mask: UInt64, parent: UInt32, alpha: Float, bounds: CGRect
			var spaces: [UInt64] = []
			var orderedIn: Bool { attrs & 0x2 != 0 }
			var minimized: Bool { tags & (1 << 60) != 0 }
			var shaped: Bool { parent == 0 && alpha > 0 && bounds.width >= 100 && bounds.height >= 50 && (level == 0 || mask & 0x20 != 0) }
		}

		func readSpaces() -> [Space] {
			let displays = spaces(conn())?.takeRetainedValue() as? [[String: Any]] ?? []
			return displays.enumerated().flatMap { di, d -> [Space] in
				let current = ((d["Current Space"] as? [String: Any])?["id64"] as? NSNumber)?.uint64Value
				return (d["Spaces"] as? [[String: Any]] ?? []).map {
					let id = ($0["id64"] as? NSNumber)?.uint64Value ?? 0
					return Space(id: id, type: ($0["type"] as? NSNumber)?.intValue ?? -1, display: di, showing: id == current)
				}
			}
		}

		/// Every row on the given Spaces, each with the Spaces that list it.
		func rows(on all: [Space]) -> [Row] {
			let cid = conn()
			var where_: [UInt32: [UInt64]] = [:], order: [UInt32] = []
			for s in all {
				var set: UInt64 = 0, clear: UInt64 = 0
				// One Space per call, because an empty Space array returns every window the server holds.
				let ids = list(cid, 0, [NSNumber(value: s.id)] as CFArray, 0x7, &set, &clear)?.takeRetainedValue() as? [NSNumber] ?? []
				for w in ids.map(\.uint32Value) {
					if where_[w] == nil { order.append(w) }
					where_[w, default: []].append(s.id)
				}
			}
			guard !order.isEmpty, let q = query(cid, order.map { NSNumber(value: $0) } as CFArray, 0)?.takeRetainedValue(),
				let it = result(Unmanaged.passUnretained(q).toOpaque())?.takeRetainedValue() else { return [] }
			let p = UnsafeRawPointer(Unmanaged.passUnretained(it).toOpaque())
			var out: [Row] = []
			// The iterator is advanced at most once per id asked for.
			for _ in order where advance(p) {
				let w = wid(p)
				out.append(Row(wid: w, pid: pid(p), level: level(p), attrs: attrs(p), tags: tags(p), mask: mask(p), parent: parent(p), alpha: alpha(p), bounds: bounds(p), spaces: where_[w] ?? []))
			}
			return out
		}

		func verdict(_ r: Row, hidden: Bool, showing: Set<UInt64>) -> String {
			guard r.shaped else { return "skip" }
			if r.minimized { return "minimized" }
			return r.orderedIn || hidden || showing.isDisjoint(with: r.spaces) ? "live" : "dead"
		}

		func candidates(_ app: NSRunningApplication) -> [Row] {
			let all = readSpaces(), showing = Set(all.filter(\.showing).map(\.id))
			return rows(on: all).filter { $0.pid == app.processIdentifier && ["live", "minimized"].contains(verdict($0, hidden: app.isHidden, showing: showing)) }
		}

		func report(_ apps: [NSRunningApplication]) {
			let t = Probe.now(), all = readSpaces(), rows = rows(on: all), showing = Set(all.filter(\.showing).map(\.id))
			print("\n== windowserver: \(all.count) spaces, \(rows.count) rows, ms=\(Probe.ms(t)) ==")
			for s in all { print("space id=\(s.id) type=\(s.type) display=\(s.display) showing=\(s.showing)") }
			for app in apps {
				let mine = rows.filter { $0.pid == app.processIdentifier }
				let verdicts = mine.map { verdict($0, hidden: app.isHidden, showing: showing) }
				let cls = verdicts.contains("live") ? "has a window" : verdicts.contains("minimized") ? "all minimized" : "no window"
				print("\(app.bundleIdentifier ?? "nil") pid=\(app.processIdentifier) hidden=\(app.isHidden): \(cls)")
				for (r, v) in zip(mine, verdicts) {
					let b = r.bounds
					print("  \(v) wid=\(r.wid) level=\(r.level) bounds=\(Int(b.minX)),\(Int(b.minY)) \(Int(b.width))x\(Int(b.height)) alpha=\(r.alpha) parent=\(r.parent) orderedIn=\(r.orderedIn) spaces=\(r.spaces) mask=0x\(String(r.mask, radix: 16)) tags=0x\(String(r.tags, radix: 16)) attrs=0x\(String(r.attrs, radix: 16))")
				}
			}
		}
	}
}
