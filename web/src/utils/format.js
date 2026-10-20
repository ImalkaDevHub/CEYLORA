const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** 20000 -> "LKR 20,000" (cents only when present). */
export function formatLkr(amount) {
  const n = Number(amount);
  if (!Number.isFinite(n)) return '';
  const hasCents = n !== Math.round(n);
  return `LKR ${n.toLocaleString('en-US', {
    minimumFractionDigits: hasCents ? 2 : 0,
    maximumFractionDigits: 2,
  })}`;
}

/** "2026-11-01" -> "1 Nov 2026". Read as a calendar date, never through a time zone. */
export function formatDateOnly(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value ?? '');
  if (!match) return value ?? '';
  return `${Number(match[3])} ${MONTHS[Number(match[2]) - 1]} ${match[1]}`;
}

/** An ISO timestamp from the API (UTC) -> "20 Oct 2026". */
export function formatTimestamp(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
}

/** A Date -> "yyyy-MM-dd" using local fields (what <input type="date"> uses). */
export function toDateInput(date) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/** Today plus `days`, as "yyyy-MM-dd". */
export function dateInputFromToday(days = 0) {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() + days);
  return toDateInput(d);
}

/** Whole nights between two "yyyy-MM-dd" dates. */
export function nightsBetween(from, to) {
  const [fy, fm, fd] = from.split('-').map(Number);
  const [ty, tm, td] = to.split('-').map(Number);
  return Math.round((Date.UTC(ty, tm - 1, td) - Date.UTC(fy, fm - 1, fd)) / 86_400_000);
}
