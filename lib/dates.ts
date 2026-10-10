function dateParts(date: Date, timeZone: string) {
  return Object.fromEntries(new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(date).map(({ type, value }) => [type, value]));
}

export function dateInputValue(timestamp: string | null, timeZone: string) {
  if (!timestamp) return "";
  try {
    const parts = dateParts(new Date(timestamp), timeZone);
    return `${parts.year}-${parts.month}-${parts.day}`;
  } catch {
    return timestamp.slice(0, 10);
  }
}

export function dateAtNineInZoneToIso(date: string, timeZone: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error("Invalid date");
  const [year, month, day] = date.split("-").map(Number);
  const calendarDate = new Date(Date.UTC(year, month - 1, day));
  if (calendarDate.getUTCFullYear() !== year || calendarDate.getUTCMonth() !== month - 1 || calendarDate.getUTCDate() !== day) throw new Error("Invalid date");
  const desired = Date.UTC(year, month - 1, day, 9, 0, 0);
  let guess = desired;
  for (let i = 0; i < 3; i += 1) {
    const parts = Object.fromEntries(new Intl.DateTimeFormat("en-CA", {
      timeZone, year: "numeric", month: "2-digit", day: "2-digit",
      hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23",
    }).formatToParts(new Date(guess)).map(({ type, value }) => [type, value]));
    const observed = Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day), Number(parts.hour), Number(parts.minute), Number(parts.second));
    guess += desired - observed;
  }
  const result = new Date(guess);
  if (!Number.isFinite(result.getTime())) throw new Error("Invalid date");
  return result.toISOString();
}
