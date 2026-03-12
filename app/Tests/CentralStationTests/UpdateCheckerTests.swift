import Testing

private func isNewer(remote: String, local: String) -> Bool {
    let r = remote.split(separator: ".").compactMap { Int($0) }
    let l = local.split(separator: ".").compactMap { Int($0) }
    for i in 0..<max(r.count, l.count) {
        let rv = i < r.count ? r[i] : 0
        let lv = i < l.count ? l[i] : 0
        if rv > lv { return true }
        if rv < lv { return false }
    }
    return false
}

@Suite("Version comparison")
struct UpdateCheckerTests {
    @Test func newerMajor() {
        #expect(isNewer(remote: "2.0.0", local: "1.0.0"))
    }

    @Test func newerMinor() {
        #expect(isNewer(remote: "1.1.0", local: "1.0.0"))
    }

    @Test func newerPatch() {
        #expect(isNewer(remote: "1.0.1", local: "1.0.0"))
    }

    @Test func sameVersion() {
        #expect(!isNewer(remote: "1.0.0", local: "1.0.0"))
    }

    @Test func olderVersion() {
        #expect(!isNewer(remote: "0.9.0", local: "1.0.0"))
    }

    @Test func mismatchedSegments() {
        #expect(isNewer(remote: "1.0.0.1", local: "1.0.0"))
        #expect(!isNewer(remote: "1.0", local: "1.0.0"))
    }
}
