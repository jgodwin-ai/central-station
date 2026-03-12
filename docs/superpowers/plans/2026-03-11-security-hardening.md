# Security Hardening Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 6 security vulnerabilities identified during red team review of Central Station.

**Architecture:** Changes span CentralStationCore (validation, file permissions, URL validation) and the executable target (hook server auth, shell escaping). Each fix is independent and can be implemented in parallel.

**Tech Stack:** Swift, Swift Testing framework, Foundation

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `app/Sources/CentralStationCore/Services/Validation.swift` | Create | `sanitizeTaskId()` and `isValidUpdateURL()` utilities |
| `app/Sources/CentralStationCore/Services/SecureFile.swift` | Create | Write files with 0600 permissions |
| `app/Sources/CentralStationCore/Services/UpdateChecker.swift` | Modify | Add URL validation |
| `app/Sources/CentralStation/Services/HookServer.swift` | Modify | Add shared secret auth |
| `app/Sources/CentralStation/Services/TerminalLauncher.swift` | Modify | Generate/embed secret in hooks, use shellEscape for mkdir |
| `app/Sources/CentralStation/Services/TaskCoordinator.swift` | Modify | Validate taskId, use SecureFile for persistence |
| `app/Sources/CentralStation/Services/RemoteStore.swift` | Modify | Use SecureFile for persistence |
| `app/Sources/CentralStation/Services/WorktreeManager.swift` | Modify | Fix mkdir shellEscape in remote extension |
| `app/Sources/CentralStation/Views/ContentView.swift` | Modify | Validate PR URL before opening |
| `app/Tests/CentralStationTests/ValidationTests.swift` | Create | Tests for sanitizeTaskId and isValidUpdateURL |
| `app/Tests/CentralStationTests/SecureFileTests.swift` | Create | Tests for 0600 file permissions |
| `app/Tests/CentralStationTests/HookServerSecurityTests.swift` | Create | Tests for secret validation logic |
| `scripts/install-hooks.sh` | Delete | Superseded by Swift installHooks() |

---

## Task 1: TaskId Sanitization

**Files:**
- Create: `app/Sources/CentralStationCore/Services/Validation.swift`
- Modify: `app/Sources/CentralStation/Services/TaskCoordinator.swift:107` (addTask)
- Modify: `app/Sources/CentralStation/Services/TaskCoordinator.swift:134` (addRemoteTask)
- Modify: `app/Sources/CentralStation/Services/TaskCoordinator.swift:59` (loadConfig)
- Create: `app/Tests/CentralStationTests/ValidationTests.swift`

**Context:** Task IDs from AddTaskSheet go through `slugify()` (alphanumeric + hyphens, max 50 chars). But IDs from config files (`ConfigLoader.load`) bypass this entirely and flow into git branch names (`cs/\(taskId)`) and shell commands. We need a validation function in CentralStationCore that rejects or sanitizes IDs with shell metacharacters.

- [ ] **Step 1: Write the test file**

```swift
// app/Tests/CentralStationTests/ValidationTests.swift
import Testing
import Foundation
@testable import CentralStationCore

@Suite("Input validation")
struct ValidationTests {
    // MARK: - sanitizeTaskId

    @Test func sanitizeSimpleId() {
        #expect(Validation.sanitizeTaskId("my-task") == "my-task")
    }

    @Test func sanitizeUppercase() {
        #expect(Validation.sanitizeTaskId("My-Task") == "my-task")
    }

    @Test func sanitizeSpaces() {
        #expect(Validation.sanitizeTaskId("my task here") == "my-task-here")
    }

    @Test func sanitizeShellMetachars() {
        #expect(Validation.sanitizeTaskId("foo'; rm -rf /; '") == "foo-rm--rf")
    }

    @Test func sanitizeEmptyReturnsEmpty() {
        #expect(Validation.sanitizeTaskId("") == "")
    }

    @Test func sanitizeTruncatesLongId() {
        let long = String(repeating: "a", count: 100)
        let result = Validation.sanitizeTaskId(long)
        #expect(result.count <= 50)
    }

    @Test func sanitizeStripsLeadingTrailingHyphens() {
        #expect(Validation.sanitizeTaskId("--hello--") == "hello")
    }

    @Test func sanitizeAlphanumericOnly() {
        #expect(Validation.sanitizeTaskId("task123") == "task123")
    }

    @Test func sanitizeSpecialChars() {
        #expect(Validation.sanitizeTaskId("hello@world#2024") == "helloworld2024")
    }

    // MARK: - isValidUpdateURL

    @Test func validGitHubURL() {
        #expect(Validation.isValidUpdateURL("https://github.com/jgodwin-ai/central-station/releases/tag/v1.0.0"))
    }

    @Test func invalidDomain() {
        #expect(!Validation.isValidUpdateURL("https://evil.com/malware"))
    }

    @Test func httpNotAllowed() {
        #expect(!Validation.isValidUpdateURL("http://github.com/jgodwin-ai/central-station/releases"))
    }

    @Test func javascriptScheme() {
        #expect(!Validation.isValidUpdateURL("javascript:alert(1)"))
    }

    @Test func emptyURL() {
        #expect(!Validation.isValidUpdateURL(""))
    }

    @Test func wrongRepo() {
        #expect(!Validation.isValidUpdateURL("https://github.com/other/repo/releases"))
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure (Validation doesn't exist yet)**

Run: `cd app && swift test --filter ValidationTests 2>&1 | tail -5`

- [ ] **Step 3: Implement Validation**

```swift
// app/Sources/CentralStationCore/Services/Validation.swift
import Foundation

public enum Validation {
    /// Sanitize a task ID for safe use in git branch names and shell commands.
    /// Allows only lowercase alphanumeric and hyphens, max 50 chars.
    public static func sanitizeTaskId(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -"))
        let filtered = lowered.unicodeScalars.filter { allowed.contains($0) }
        let cleaned = String(String.UnicodeScalarView(filtered))
        let slug = cleaned
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let trimmed = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if trimmed.count > 50 {
            return String(trimmed.prefix(50)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        return trimmed
    }

    /// Validate that an update URL points to the expected GitHub repository over HTTPS.
    public static func isValidUpdateURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              url.scheme == "https",
              url.host == "github.com",
              url.path.hasPrefix("/jgodwin-ai/central-station/") else {
            return false
        }
        return true
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

Run: `cd app && swift test --filter ValidationTests 2>&1 | tail -10`

- [ ] **Step 5: Wire sanitizeTaskId into TaskCoordinator**

In `TaskCoordinator.swift`, sanitize the `id` parameter in `addTask()`, `addRemoteTask()`, and sanitize config-loaded IDs in `loadConfig()`:

```swift
// In addTask() — sanitize the id parameter:
let sanitizedId = Validation.sanitizeTaskId(id)
// Use sanitizedId everywhere instead of id

// In addRemoteTask() — same:
let sanitizedId = Validation.sanitizeTaskId(id)

// In loadConfig() — sanitize config IDs:
let sanitizedId = Validation.sanitizeTaskId(taskConfig.id)
guard !sanitizedId.isEmpty else { continue }
guard !tasks.contains(where: { $0.id == sanitizedId }) else { continue }
let task = AppTask(config: taskConfig, worktreePath: "", projectPath: self.projectPath)
// Note: AppTask.init(config:) uses taskConfig.id directly, so we need to
// sanitize at the TaskConfig level or override the id after creation
```

- [ ] **Step 6: Run full test suite**

Run: `cd app && swift test 2>&1 | tail -10`

- [ ] **Step 7: Commit**

---

## Task 2: Hook Server Shared Secret

**Files:**
- Modify: `app/Sources/CentralStation/Services/HookServer.swift`
- Modify: `app/Sources/CentralStation/Services/TerminalLauncher.swift`
- Create: `app/Tests/CentralStationTests/HookServerSecurityTests.swift`

**Context:** The hook server on localhost:19280 has no authentication. Any local process can spoof hook events. Generate a random secret at app launch, embed it in the curl hook commands as a `Authorization: Bearer <secret>` header, and validate it on every incoming request.

- [ ] **Step 1: Write tests**

```swift
// app/Tests/CentralStationTests/HookServerSecurityTests.swift
import Testing
import Foundation
@testable import CentralStationCore

@Suite("Hook server security")
struct HookServerSecurityTests {
    @Test func secretIsNonEmpty() {
        let secret = HookSecret.generate()
        #expect(!secret.isEmpty)
    }

    @Test func secretIsReasonableLength() {
        let secret = HookSecret.generate()
        #expect(secret.count >= 32)
    }

    @Test func secretsAreDifferent() {
        let a = HookSecret.generate()
        let b = HookSecret.generate()
        #expect(a != b)
    }

    @Test func validateCorrectSecret() {
        let secret = HookSecret.generate()
        #expect(HookSecret.validate(header: "Bearer \(secret)", expected: secret))
    }

    @Test func validateWrongSecret() {
        #expect(!HookSecret.validate(header: "Bearer wrong", expected: "correct"))
    }

    @Test func validateMissingBearer() {
        let secret = HookSecret.generate()
        #expect(!HookSecret.validate(header: secret, expected: secret))
    }

    @Test func validateEmptyHeader() {
        #expect(!HookSecret.validate(header: "", expected: "secret"))
    }
}
```

- [ ] **Step 2: Create HookSecret in CentralStationCore**

```swift
// app/Sources/CentralStationCore/Services/HookSecret.swift
import Foundation

public enum HookSecret {
    public static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    public static func validate(header: String, expected: String) -> Bool {
        guard header.hasPrefix("Bearer ") else { return false }
        let token = String(header.dropFirst("Bearer ".count))
        // Constant-time comparison to prevent timing attacks
        guard token.count == expected.count else { return false }
        var result: UInt8 = 0
        for (a, b) in zip(token.utf8, expected.utf8) {
            result |= a ^ b
        }
        return result == 0
    }
}
```

- [ ] **Step 3: Run tests — expect pass**

- [ ] **Step 4: Add secret to HookServer**

In `HookServer.swift`:
- Add `var secret: String = ""` property
- In `processRequest()`, extract the Authorization header and validate with `HookSecret.validate()`
- Return 401 if invalid

- [ ] **Step 5: Embed secret in hook commands**

In `TerminalLauncher.swift`:
- `installHooks()` and `installHooksOnRemote()` accept a `secret` parameter
- Add `-H 'Authorization: Bearer \(secret)'` to all curl commands

- [ ] **Step 6: Wire up in TaskCoordinator**

In `TaskCoordinator.start()`:
- Generate secret: `let secret = HookSecret.generate()`
- Set `hookServer.secret = secret`
- Pass secret to `installHooks(secret:)` calls

- [ ] **Step 7: Run full test suite**

- [ ] **Step 8: Commit**

---

## Task 3: File Permissions (0600)

**Files:**
- Create: `app/Sources/CentralStationCore/Services/SecureFile.swift`
- Modify: `app/Sources/CentralStation/Services/TaskCoordinator.swift:56`
- Modify: `app/Sources/CentralStation/Services/RemoteStore.swift` (find write call)
- Create: `app/Tests/CentralStationTests/SecureFileTests.swift`

**Context:** Persisted JSON files (tasks, remotes, chime settings) are written with default permissions (0644 — world-readable). They contain session IDs, prompts, SSH hosts. Should be 0600.

- [ ] **Step 1: Write tests**

```swift
// app/Tests/CentralStationTests/SecureFileTests.swift
import Testing
import Foundation
@testable import CentralStationCore

@Suite("Secure file writing")
struct SecureFileTests {
    @Test func writesWithRestrictedPermissions() throws {
        let path = NSTemporaryDirectory() + "secure-test-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }

        try SecureFile.write(Data("test".utf8), to: path)

        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let perms = (attrs[.posixPermissions] as? Int) ?? 0
        #expect(perms == 0o600)
    }

    @Test func writesCorrectContent() throws {
        let path = NSTemporaryDirectory() + "secure-test-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let content = Data("{\"key\":\"value\"}".utf8)
        try SecureFile.write(content, to: path)

        let read = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(read == content)
    }

    @Test func overwritesExistingFile() throws {
        let path = NSTemporaryDirectory() + "secure-test-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }

        try SecureFile.write(Data("first".utf8), to: path)
        try SecureFile.write(Data("second".utf8), to: path)

        let read = String(data: try Data(contentsOf: URL(fileURLWithPath: path)), encoding: .utf8)
        #expect(read == "second")
    }

    @Test func createsParentDirectoryIfNeeded() throws {
        let dir = NSTemporaryDirectory() + "secure-nested-\(UUID().uuidString)"
        let path = dir + "/file.json"
        defer { try? FileManager.default.removeItem(atPath: dir) }

        try SecureFile.write(Data("test".utf8), to: path)

        #expect(FileManager.default.fileExists(atPath: path))
    }
}
```

- [ ] **Step 2: Implement SecureFile**

```swift
// app/Sources/CentralStationCore/Services/SecureFile.swift
import Foundation

public enum SecureFile {
    /// Write data to a file with 0600 (owner read/write only) permissions.
    public static func write(_ data: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent().path
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: dir, isDirectory: &isDir) {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        try data.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
}
```

- [ ] **Step 3: Run tests — expect pass**

- [ ] **Step 4: Replace bare writes in TaskCoordinator and RemoteStore**

In `TaskCoordinator.saveTasks()` replace:
```swift
try? data.write(to: URL(fileURLWithPath: Self.persistencePath))
```
with:
```swift
try? SecureFile.write(data, to: Self.persistencePath)
```

Do the same for RemoteStore and ChimeSettings write paths.

- [ ] **Step 5: Run full test suite**

- [ ] **Step 6: Commit**

---

## Task 4: Update URL Validation

**Files:**
- Modify: `app/Sources/CentralStation/Views/ContentView.swift:27-28`
- Modify: `app/Sources/CentralStation/Views/ContentView.swift:162-163`

**Context:** The update checker returns a URL from GitHub's API and opens it with `NSWorkspace.shared.open()`. If the API response is poisoned, a malicious URL could be opened. Validate with `Validation.isValidUpdateURL()` before opening.

Also validate PR URLs returned by `gh pr create` — these should start with `https://github.com/`.

- [ ] **Step 1: Add PR URL validation to Validation.swift**

```swift
/// Validate that a PR URL points to GitHub over HTTPS.
public static func isValidPRURL(_ urlString: String) -> Bool {
    guard let url = URL(string: urlString),
          url.scheme == "https",
          url.host == "github.com" else {
        return false
    }
    return true
}
```

- [ ] **Step 2: Add tests for isValidPRURL**

Add to `ValidationTests.swift`:
```swift
@Test func validPRURL() {
    #expect(Validation.isValidPRURL("https://github.com/user/repo/pull/123"))
}

@Test func invalidPRURL() {
    #expect(!Validation.isValidPRURL("https://evil.com/phish"))
}
```

- [ ] **Step 3: Wire validation into ContentView**

In `ContentView.swift` line 27-28, wrap with validation:
```swift
if let url = URL(string: update.url), Validation.isValidUpdateURL(update.url) {
    NSWorkspace.shared.open(url)
}
```

In `ContentView.swift` line 162-163, wrap PR URL:
```swift
if let prURL, let url = URL(string: prURL), Validation.isValidPRURL(prURL) {
    NSWorkspace.shared.open(url)
}
```

- [ ] **Step 4: Run full test suite**

- [ ] **Step 5: Commit**

---

## Task 5: Shell Escaping Fix + Delete install-hooks.sh

**Files:**
- Modify: `app/Sources/CentralStation/Services/WorktreeManager.swift:41`
- Delete: `scripts/install-hooks.sh`

**Context:** The remote `createWorktreeRemote` uses manual quote wrapping `'...'` for `mkdir -p` instead of the `shellEscape()` function used everywhere else. Fix for consistency. Also delete the bash `install-hooks.sh` since the Swift `installHooks()` properly preserves existing settings (the bash script clobbers them).

- [ ] **Step 1: Fix shellEscape in remote mkdir**

In `app/Sources/CentralStation/Services/WorktreeManager.swift` line 41, change:
```swift
_ = try? await RemoteShell.run(host: host, command: "mkdir -p '\(worktreesDir)'")
```
to:
```swift
_ = try? await RemoteShell.run(host: host, command: "mkdir -p \(RemoteShell.shellEscape(worktreesDir))")
```

This requires making `RemoteShell.shellEscape` non-private (`static` instead of `private static`).

In `RemoteShell.swift` line 55, change:
```swift
private static func shellEscape(_ str: String) -> String {
```
to:
```swift
static func shellEscape(_ str: String) -> String {
```

- [ ] **Step 2: Delete install-hooks.sh**

Remove `scripts/install-hooks.sh`.

- [ ] **Step 3: Run full test suite**

- [ ] **Step 4: Commit**

---

## Execution Order

Tasks 1-5 are independent and can be dispatched in parallel to subagents. Each produces self-contained, testable changes.
