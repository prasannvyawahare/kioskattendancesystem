"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";

const NAV_ITEMS: { href: string; label: string; icon: ReactNode }[] = [
  {
    href: "/dashboard",
    label: "Dashboard",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.5} className="h-5 w-5">
        <rect x="3.5" y="3.5" width="7" height="7" rx="1.5" stroke="currentColor" />
        <rect x="13.5" y="3.5" width="7" height="7" rx="1.5" stroke="currentColor" />
        <rect x="3.5" y="13.5" width="7" height="7" rx="1.5" stroke="currentColor" />
        <rect x="13.5" y="13.5" width="7" height="7" rx="1.5" stroke="currentColor" />
      </svg>
    ),
  },
  {
    href: "/employees",
    label: "Students",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.5} className="h-5 w-5">
        <circle cx="12" cy="8" r="3.25" stroke="currentColor" />
        <path d="M4.5 20c1.2-4 4-6 7.5-6s6.3 2 7.5 6" stroke="currentColor" strokeLinecap="round" />
      </svg>
    ),
  },
  {
    href: "/attendance",
    label: "Attendance",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.5} className="h-5 w-5">
        <rect x="4.5" y="4.5" width="15" height="16" rx="2" stroke="currentColor" />
        <path d="M8 3v3M16 3v3M4.5 9.5h15" stroke="currentColor" strokeLinecap="round" />
        <path d="M8.5 14l2 2 4-4" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    ),
  },
  {
    href: "/attendance/register",
    label: "Register",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.5} className="h-5 w-5">
        <rect x="3.5" y="4.5" width="17" height="15" rx="2" stroke="currentColor" />
        <path
          d="M3.5 9.5h17M8.5 4.5v15M13.5 4.5v15"
          stroke="currentColor"
          strokeLinecap="round"
        />
      </svg>
    ),
  },
  {
    href: "/settings",
    label: "Settings",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.5} className="h-5 w-5">
        <circle cx="12" cy="12" r="3" stroke="currentColor" />
        <path
          d="M19.4 13.5a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 11-2.83 2.83l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V19.5a2 2 0 11-4 0v-.09a1.65 1.65 0 00-1-1.51 1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 11-2.83-2.83l.06-.06a1.65 1.65 0 00.33-1.82 1.65 1.65 0 00-1.51-1H4.5a2 2 0 110-4h.09a1.65 1.65 0 001.51-1 1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 112.83-2.83l.06.06a1.65 1.65 0 001.82.33h.06a1.65 1.65 0 001-1.51V4.5a2 2 0 114 0v.09a1.65 1.65 0 001 1.51h.06a1.65 1.65 0 001.82-.33l.06-.06a2 2 0 112.83 2.83l-.06.06a1.65 1.65 0 00-.33 1.82v.06a1.65 1.65 0 001.51 1h.09a2 2 0 110 4h-.09a1.65 1.65 0 00-1.51 1z"
          stroke="currentColor"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    ),
  },
];

export function SideNav({ className = "flex flex-col gap-1" }: { className?: string }) {
  const pathname = usePathname();

  return (
    <nav className={className}>
      {NAV_ITEMS.map((item) => {
        const active =
          pathname === item.href ||
          (item.href !== "/attendance" && pathname?.startsWith(`${item.href}/`)) ||
          // /attendance itself shouldn't stay highlighted while on /attendance/register
          (item.href === "/attendance" && pathname === "/attendance");
        return (
          <Link
            key={item.href}
            href={item.href}
            className={
              active
                ? "flex items-center gap-3 rounded-lg bg-indigo-50 px-3 py-2 text-sm font-medium text-indigo-700"
                : "flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100 hover:text-slate-900"
            }
          >
            {item.icon}
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}
