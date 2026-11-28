import Foundation

/// Messages between Triwarden and its auto-type helper (one frame each way per request), over a short Unix socket whose path is published in the
/// App Group container. The helper types only for Triwarden itself, and only into the app it's told to.
public enum AutoTypeProtocol {
    /// The socket's file name (and the stem of its App Group pointer file).
    public static let socketName = "autotype.sock"

    public struct Request: Codable, Sendable {
        public enum Step: Codable, Sendable, Equatable {
            case text(String)
            case tab
            case enter
        }

        public enum Action: Codable, Sendable { case status, askPermission, type }

        public var action: Action
        /// The app to type into (it's brought forward first).
        public var pid: Int32 = 0
        public var steps: [Step] = []

        public init(action: Action, pid: Int32 = 0, steps: [Step] = []) {
            self.action = action
            self.pid = pid
            self.steps = steps
        }
    }

    public struct Response: Codable, Sendable {
        public enum Failure: String, Codable, Sendable {
            /// Accessibility isn't allowed for the helper yet.
            case permission
            /// The app to type into quit or couldn't come forward.
            case target
            case badRequest
        }

        public var trusted: Bool
        public var failure: Failure?

        public init(trusted: Bool, failure: Failure? = nil) {
            self.trusted = trusted
            self.failure = failure
        }
    }
}
