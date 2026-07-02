import Testing
@testable import WorderCore

@Test func packageVersionIsSet() {
    #expect(!WorderCore.version.isEmpty)
}
