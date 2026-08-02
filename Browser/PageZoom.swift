import CoreGraphics

nonisolated enum PageZoom {
    static let actualSize: CGFloat = 1.0

    private static let levels: [CGFloat] = [
        0.25,
        0.33,
        0.50,
        0.67,
        0.75,
        0.80,
        0.90,
        actualSize,
        1.10,
        1.25,
        1.50,
        1.75,
        2.00,
        2.50,
        3.00,
        4.00,
        5.00,
    ]

    private static let comparisonTolerance: CGFloat = 0.0001

    static var minimum: CGFloat { levels[0] }
    static var maximum: CGFloat { levels[levels.count - 1] }

    static func increased(from current: CGFloat) -> CGFloat {
        levels.first { $0 > current + comparisonTolerance } ?? maximum
    }

    static func decreased(from current: CGFloat) -> CGFloat {
        levels.last { $0 < current - comparisonTolerance } ?? minimum
    }

    static func canIncrease(_ current: CGFloat) -> Bool {
        current < maximum - comparisonTolerance
    }

    static func canDecrease(_ current: CGFloat) -> Bool {
        current > minimum + comparisonTolerance
    }

    static func isActualSize(_ current: CGFloat) -> Bool {
        abs(current - actualSize) <= comparisonTolerance
    }
}
