import Foundation

/// A threshold table: an ascending list of `(lower bound, value)` rows, looked up
/// by a scalar.
///
/// ## Why this exists
/// Nearly every rule in this app is a band — wave height to slang, knots to a
/// wind word, score to a colour. Written as `if`/`else` chains those bands end up
/// scattered through the engine and drift out of step with the thresholds in
/// `surf_research.md`. Written as a table they are one readable literal a local
/// surfer can check line by line, and settling the disputed 1.5–2.2 m `overhead`
/// band becomes a one-row edit rather than surgery on a conditional.
///
/// Rows are validated on construction: non-empty and strictly ascending. An
/// out-of-order bound would silently shadow a whole band, which is exactly the
/// class of bug a table is supposed to make impossible.
///
/// The first row is the floor — anything below it resolves to that row. That is
/// what makes the lookup total and lets it return a non-optional, so no caller
/// ever has to invent a fallback band.
public struct RuleTable<Value: Sendable>: Sendable {
    public struct Row: Sendable {
        /// Inclusive lower bound of this band.
        public let lowerBound: Double
        public let value: Value

        public init(from lowerBound: Double, _ value: Value) {
            self.lowerBound = lowerBound
            self.value = value
        }
    }

    public let rows: [Row]

    public init(_ rows: [Row]) {
        precondition(!rows.isEmpty, "A rule table needs at least one row")
        precondition(
            zip(rows, rows.dropFirst()).allSatisfy { $0.lowerBound < $1.lowerBound },
            "Rule table rows must be strictly ascending; an out-of-order bound shadows a band"
        )
        self.rows = rows
    }

    /// The band `input` falls in. Total by construction.
    public func value(for input: Double) -> Value {
        for row in rows.reversed() where input >= row.lowerBound {
            return row.value
        }
        return rows[0].value
    }

    /// Exclusive upper bound of the band starting at `rows[index]`, or `nil` for
    /// the open-ended top band.
    public func upperBound(atRow index: Int) -> Double? {
        index + 1 < rows.count ? rows[index + 1].lowerBound : nil
    }
}

public extension RuleTable where Value: Equatable {
    /// The bound at which `value` starts, or `nil` when it is not in the table.
    ///
    /// Lets an enum publish its own threshold without restating it, so the table
    /// stays the single source of truth for where a band begins.
    func lowerBound(of value: Value) -> Double? {
        rows.first { $0.value == value }?.lowerBound
    }
}
