export function pad(n: number): string {
  return String(n).padStart(2, "0");
}

// Pinned locale/options rather than a bare toLocaleTimeString()/
// toLocaleString() -- those fall back to the runtime's default locale, which
// differs between the Node server process (SSR) and the visitor's browser
// (hydration), producing the same instant in two different strings (e.g.
// "10:08:28 PM" vs "22:08:28") and tripping React's hydration mismatch
// check on any "use client" component that renders one directly.
export function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString("en-US", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

export function formatDateTime(iso: string): string {
  return new Date(iso).toLocaleString("en-US", {
    dateStyle: "medium",
    timeStyle: "medium",
  });
}

export function todayIso(): string {
  const now = new Date();
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}
