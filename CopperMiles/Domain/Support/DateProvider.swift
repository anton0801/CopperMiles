import Foundation

/// Supplies "now" to the domain.
///
/// Trip rules are almost entirely about time — an arrival cannot be in the future,
/// an end cannot precede the last event — so the current date is an explicit
/// dependency rather than a scattering of `Date()` calls. Tests substitute a fixed
/// date and get the same answer every run.
protocol DateProvider {
  var now: Date { get }
}

struct SystemDateProvider: DateProvider {
  var now: Date { Date() }
}

struct FixedDateProvider: DateProvider {
  var now: Date

  init(_ now: Date) {
    self.now = now
  }
}
