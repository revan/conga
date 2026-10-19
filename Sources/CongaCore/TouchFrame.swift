/// One contact on the trackpad. `x` and `y` are normalised to 0...1 across the surface.
public struct Touch: Equatable, Sendable {
    public var id: Int
    public var x: Double
    public var y: Double
    /// What MultitouchSupport takes the contact to be: 1 is the thumb, 2...5 the fingers, and
    /// 6 and 7 parts of the palm. 0 when unknown.
    public var part: Int

    public init(id: Int, x: Double, y: Double, part: Int = 0) {
        self.id = id
        self.x = x
        self.y = y
        self.part = part
    }

    /// The framework labels a palm as one from its first frame, while it is still as small as
    /// a fingertip, so this is more reliable than its size.
    public var isPalm: Bool { part >= 6 }
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
