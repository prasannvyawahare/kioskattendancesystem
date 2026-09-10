"use client";

import type { FormEvent } from "react";
import { deleteEmployee } from "../actions";

export function DeleteEmployeeButton({ employeeId, fullName }: { employeeId: string; fullName: string }) {
  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    if (!confirm(`Delete ${fullName}? This removes their enrollment photos too and can't be undone.`)) {
      event.preventDefault();
    }
  }

  return (
    <form action={deleteEmployee.bind(null, employeeId)} onSubmit={handleSubmit}>
      <button type="submit" className="text-sm font-medium text-red-600 hover:text-red-700">
        Delete
      </button>
    </form>
  );
}
