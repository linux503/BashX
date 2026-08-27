import Foundation

struct TrafficSample: Equatable, Identifiable {
    let id = UUID()
    var up: Int64
    var down: Int64
    var at: Date
}
