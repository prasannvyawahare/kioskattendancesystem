/// Hardcoded Asia/Kolkata (+05:30, no DST) day-boundary helper, mirroring
/// the equally hardcoded `at time zone 'Asia/Kolkata'` computation in
/// mark_attendance() (supabase/migrations/0012_min_checkout_gap.sql /
/// 0013_offline_sync.sql) -- the offline decision engine has to agree with
/// the server on what "today" is, or a scan near midnight could be filed
/// under a different event_date locally than the server would pick. Change
/// this alongside the SQL side if kiosks are ever deployed elsewhere.
///
/// Only [todayKey] is safe to use for the shifted IST value -- it reads
/// out .year/.month/.day only. For any timestamp that gets serialized,
/// stored, sent to the server, or diffed against another timestamp
/// (scanned_at, check-in instants, min-gap comparisons), use [nowUtc]:
/// real elapsed-time/instant math doesn't need timezone shifting, only day
/// bucketing does, and shifting a UTC-flagged DateTime's wall-clock value
/// while leaving isUtc=true (as an earlier version of this class did)
/// silently mislabels its ISO-8601 string with the wrong offset.
class IstClock {
  static const _offset = Duration(hours: 5, minutes: 30);

  /// The real current instant. Use this for anything serialized, stored,
  /// or diffed -- never the IST-shifted value below.
  static DateTime nowUtc() => DateTime.now().toUtc();

  /// yyyy-MM-dd in Asia/Kolkata, matching Postgres's `::date` cast. Do not
  /// serialize or diff the underlying shifted DateTime -- extract fields
  /// from it (as this method does) and nothing else.
  static String todayKey() => dateKeyDaysAgo(0);

  /// Same as [todayKey] but [days] earlier -- e.g. for pruning local state
  /// older than a retention window. Still IST-bucketed, still read-only
  /// (field extraction, never diffed/serialized), same rule as [todayKey].
  static String dateKeyDaysAgo(int days) {
    final ist = nowUtc().add(_offset).subtract(Duration(days: days));
    final y = ist.year.toString().padLeft(4, '0');
    final m = ist.month.toString().padLeft(2, '0');
    final d = ist.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
