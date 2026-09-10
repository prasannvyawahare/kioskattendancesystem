"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";

export function SettingsToast({ saved }: { saved?: string }) {
  const router = useRouter();
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (!saved) return;
    setVisible(true);
    const hide = setTimeout(() => setVisible(false), 2500);
    // Strips ?saved=1 from the URL once the toast is gone, so a refresh
    // doesn't replay it.
    const clear = setTimeout(() => router.replace("/settings"), 2800);
    return () => {
      clearTimeout(hide);
      clearTimeout(clear);
    };
  }, [saved, router]);

  if (!saved) return null;

  return (
    <div
      role="status"
      aria-live="polite"
      className={`fixed bottom-6 right-6 z-50 rounded-lg bg-slate-900 px-4 py-3 text-sm font-medium text-white shadow-lg transition-opacity duration-300 ${
        visible ? "opacity-100" : "opacity-0"
      }`}
    >
      Settings saved.
    </div>
  );
}
