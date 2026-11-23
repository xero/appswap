import Testing
@testable import appswap

@MainActor @Suite struct PrivateTests {
	@Test func aMissingSymbolIsNil() {
		#expect(Private.address("appswap_no_such_symbol") == nil)
		let f: (@convention(c) () -> Int32)? = Private.bind("appswap_no_such_symbol")
		#expect(f == nil)
	}

	@Test func aPublicSymbolResolves() {
		#expect(Private.address("AXIsProcessTrusted") != nil)
	}

	@Test func theRunnerRecordsAnSDK() {
		#expect(Build.linkedSDK != nil)
	}
}
