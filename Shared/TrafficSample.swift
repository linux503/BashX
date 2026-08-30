import Foundation

struct TrafficSample: Equatable, Identifiable {
    /// Stable identity for SwiftUI charts (UUID-per-sample caused layout thrash).
    var id: TimeInterval { at.timeIntervalSinceReferenceDate }
    var up: Int64
    var down: Int64
    var at: Date
}
