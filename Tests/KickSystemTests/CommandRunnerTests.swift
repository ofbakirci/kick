import Foundation
import XCTest
@testable import KickSystem

final class CommandRunnerTests: XCTestCase {
    func testCapturesOutputWithoutAShell() async throws {
        let result = try await SystemCommandRunner(timeout: 1).run(
            executable: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["hello"]
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(String(decoding: result.standardOutput, as: UTF8.self), "hello")
        XCTAssertTrue(result.standardError.isEmpty)
    }

    func testTimesOutAndStopsTheChild() async throws {
        let started = Date()

        do {
            _ = try await SystemCommandRunner(timeout: 0.08).run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap '' TERM; sleep 2"]
            )
            XCTFail("Expected a timeout")
        } catch let error as CommandRunnerError {
            guard case .timedOut = error else {
                return XCTFail("Expected timedOut, got \(error)")
            }
        }

        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
    }

    func testCancellationStopsTheChild() async throws {
        let started = Date()
        let task = Task {
            try await SystemCommandRunner(timeout: 10).run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"]
            )
        }

        try await Task.sleep(nanoseconds: 80_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
    }
}
