"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

/// Re-runs the enclosing Server Component's data fetch on an interval via
/// router.refresh() -- for pages showing data that changes from outside
/// the admin panel itself (kiosk enrollment/attendance writes), where
/// there's no user action to hang a refetch off of. Renders nothing.
export function AutoRefresh({ intervalMs = 5000 }: { intervalMs?: number }) {
  const router = useRouter();

  useEffect(() => {
    const id = setInterval(() => router.refresh(), intervalMs);
    return () => clearInterval(id);
  }, [router, intervalMs]);

  return null;
}
