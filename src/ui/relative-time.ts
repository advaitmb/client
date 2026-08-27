/**
 * "3 minutes ago", "1 day ago" — the save indicator's relative timestamps.
 *
 * Replaces Translation.timeDistInWords, which wrapped the gingko/time-distance
 * package. Intl.RelativeTimeFormat is built into the platform and already
 * knows the plural rules, so the dependency goes with it.
 */

const UNITS: Array<[limit: number, seconds: number, unit: Intl.RelativeTimeFormatUnit]> = [
  [60, 1, "second"],
  [3600, 60, "minute"],
  [86400, 3600, "hour"],
  [604800, 86400, "day"],
  [2629800, 604800, "week"],
  [31557600, 2629800, "month"],
  [Infinity, 31557600, "year"],
];

const fmt = new Intl.RelativeTimeFormat("en", { numeric: "auto" });

/** `from` and `to` are epoch milliseconds. */
export function relativeTime(from: number, to: number): string {
  const deltaSeconds = Math.round((from - to) / 1000);
  const abs = Math.abs(deltaSeconds);
  if (abs < 20) return "just now";

  for (const [limit, perUnit, unit] of UNITS) {
    if (abs < limit) return fmt.format(Math.round(deltaSeconds / perUnit), unit);
  }
  return fmt.format(Math.round(deltaSeconds / 31557600), "year");
}
