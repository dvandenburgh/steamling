export function clone<T>(obj: T): T {
  return JSON.parse(JSON.stringify(obj));
}

// Decimal units, the way Steam and file managers show sizes.
export function formatBytes(bytes: number): string {
  if (bytes < 1e6) return `${Math.max(0, Math.round(bytes / 1e3))} KB`;
  if (bytes < 1e9) return `${Math.round(bytes / 1e6)} MB`;
  return `${(bytes / 1e9).toFixed(1)} GB`;
}

// What a failed backend call says, without the "Error: " the runtime puts in front of it.
export function errorText(error: unknown): string {
  return String((error as any)?.message ?? error).replace(/^(\w*Error|Exception): /, "");
}
