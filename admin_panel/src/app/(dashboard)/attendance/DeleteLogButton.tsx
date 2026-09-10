"use client";

import type { FormEvent } from "react";
import { deleteAttendanceLog } from "./actions";

export function DeleteLogButton({ logId, label }: { logId: string; label: string }) {
  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    if (!confirm(`Delete this ${label} record? This can't be undone.`)) {
      event.preventDefault();
    }
  }

  return (
    <form action={deleteAttendanceLog.bind(null, logId)} onSubmit={handleSubmit}>
      <button type="submit" className="text-sm font-medium text-red-600 hover:text-red-700">
        Delete
      </button>
    </form>
  );
}
