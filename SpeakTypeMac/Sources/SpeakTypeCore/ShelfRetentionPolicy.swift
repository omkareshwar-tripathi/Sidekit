import Foundation

/// How long the Shelf keeps an item before it auto-expires. Drag-out never deletes (reuse-safe),
/// so this timer + manual remove are the only ways items leave. Configurable in Settings; defaults
/// to 48h ("park it for a day or two").
public struct ShelfRetentionPolicy: Sendable, Equatable {
    public var ttl: Duration

    public init(ttl: Duration = .seconds(48 * 3600)) {
        self.ttl = ttl
    }

    public static let `default` = ShelfRetentionPolicy()
}
