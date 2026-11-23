import Darwin

/// Private symbols are looked up at run time, so a missing one is a nil and never a launch failure.
enum Private {
	static let names = [
		"CGSMainConnectionID", "CGSCopyManagedDisplaySpaces", "CGSCopyWindowsWithOptionsAndTags",
		"SLSWindowQueryWindows", "SLSWindowQueryResultCopyWindows", "SLSWindowIteratorAdvance",
		"SLSWindowIteratorGetWindowID", "SLSWindowIteratorGetPID", "SLSWindowIteratorGetLevel",
		"SLSWindowIteratorGetTags", "SLSWindowIteratorGetAttributes", "SLSWindowIteratorGetSpaceTypeMask",
		"SLSWindowIteratorGetParentID", "SLSWindowIteratorGetAlpha", "SLSWindowIteratorGetBounds",
		"SLSSpaceSetFrontPSN", "_SLPSSetFrontProcessWithOptions", "SLPSPostEventRecordTo",
		"_AXUIElementGetWindow", "GetProcessForPID", "CGSSetSymbolicHotKeyEnabled",
	]

	// Nothing links SkyLight, so it has to be loaded before the default lookup can see its symbols.
	private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

	static func address(_ name: String) -> UnsafeMutableRawPointer? {
		_ = skyLight
		// -2 is RTLD_DEFAULT, a C macro Swift doesn't import.
		return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
	}

	static func bind<T>(_ name: String) -> T? { address(name).map { unsafeBitCast($0, to: T.self) } }
}
