import Foundation

/// Clock formatting shared by the game timer, the win sheet and Stats.
///
/// Both of these lived as private copies inside views, which is how the two
/// bugs below survived: a 72-minute solve rendered as "72:14", and a first
/// solve under a minute rendered as "0m played", which reads as broken rather
/// than as rounding.
nonisolated enum TimeFormatting {

    /// A running or finished puzzle time: `4:07`, or `1:12:33` past an hour.
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// A lifetime total, in the coarsest unit that still says something true:
    /// `45s`, `12m`, `3h 04m`.
    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes)m" }
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }
}
