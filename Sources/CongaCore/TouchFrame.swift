/// One finger on the trackpad. `x` and `y` are normalised to 0...1 across the surface.
public struct Touch: Equatable, Sendable {
    public var id: Int
    public var x: Double
    public var y: Double

    public init(id: Int, x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }
}

/// All fingers currently down on one trackpad at one instant.
public struct TouchFrame: Equatable, Sendable {
    public var timestamp: Double
    public var touches: [Touch]

    public init(timestamp: Double = 0, touches: [Touch]) {
        self.timestamp = timestamp
        self.touches = touches
    }
}
