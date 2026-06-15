const RELATIVE_TIME_RE = /^(\d+)\s*(s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days)$/i;

const UNIT_MS: Record<string, number> = {
  s: 1000,
  sec: 1000,
  secs: 1000,
  second: 1000,
  seconds: 1000,
  m: 60_000,
  min: 60_000,
  mins: 60_000,
  minute: 60_000,
  minutes: 60_000,
  h: 3_600_000,
  hr: 3_600_000,
  hrs: 3_600_000,
  hour: 3_600_000,
  hours: 3_600_000,
  d: 86_400_000,
  day: 86_400_000,
  days: 86_400_000
};

export type Clock = () => Date;

export function parseTime(value: string | undefined, now: Date): string | undefined {
  if (!value) {
    return undefined;
  }

  const trimmed = value.trim();
  const relative = RELATIVE_TIME_RE.exec(trimmed);
  if (relative) {
    const amount = Number(relative[1]);
    const unit = relative[2].toLowerCase();
    return new Date(now.getTime() + amount * UNIT_MS[unit]).toISOString();
  }

  const parsed = new Date(trimmed);
  if (Number.isNaN(parsed.getTime())) {
    throw new Error(`Invalid time value: ${value}`);
  }
  return parsed.toISOString();
}

export function isDue(value: string | undefined, now: Date): boolean {
  return Boolean(value && new Date(value).getTime() <= now.getTime());
}
