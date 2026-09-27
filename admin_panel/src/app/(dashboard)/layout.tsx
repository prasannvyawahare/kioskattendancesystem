import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOut } from "./actions";
import { SideNav } from "./SideNav";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/login");

  // Moved here from middleware.ts: middleware runs on every request
  // (including the RSC-payload fetch behind every sidebar click), while this
  // layout only re-runs once per dashboard visit thanks to Next.js's client
  // router cache -- so the same authorization check no longer costs a
  // Postgres round-trip on every navigation.
  const { data: profile } = await supabase
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .single();

  if (profile?.role !== "admin") {
    await supabase.auth.signOut();
    redirect("/login?error=not_authorized");
  }

  return (
    <div className="flex min-h-screen bg-[#F3F4FB]">
      {/* Desktop sidebar */}
      <aside className="relative hidden w-64 shrink-0 flex-col overflow-hidden bg-gradient-to-b from-[#4C3494] via-[#5B3FA0] to-[#2E2158] md:flex print:hidden">
        {/* Decorative background blobs -- purely visual, sits behind everything. */}
        <div className="pointer-events-none absolute inset-0 overflow-hidden" aria-hidden>
          <div className="absolute -left-16 -top-20 h-56 w-56 rounded-full bg-white/10 blur-3xl" />
          <div className="absolute -right-20 top-1/3 h-64 w-64 rounded-full bg-fuchsia-400/10 blur-3xl" />
          <div className="absolute -bottom-24 left-1/4 h-64 w-64 rounded-full bg-indigo-300/10 blur-3xl" />
        </div>

        <div className="relative flex items-center gap-3 px-6 py-6">
          <span
            className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-white text-violet-700 shadow-md shadow-black/10"
            aria-hidden
          >
            <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.75} className="h-6 w-6">
              <path
                d="M4 6.5l8-3 8 3-8 3-8-3z"
                stroke="currentColor"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
              <path
                d="M7 8.5v5c0 1.5 2.2 2.5 5 2.5s5-1 5-2.5v-5"
                stroke="currentColor"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
          </span>
          <div className="leading-tight">
            <span className="block font-semibold text-white">Attendance Admin</span>
            <span className="block text-xs text-white/50">Kiosk console</span>
          </div>
        </div>
        <SideNav variant="sidebar" className="relative flex flex-1 flex-col gap-1 px-4 py-2" />
        <div className="relative mx-4 mb-4 rounded-2xl bg-white/10 p-3 backdrop-blur-sm">
          <p className="truncate px-1 pb-2 text-xs text-white/60">{user.email}</p>
          <form action={signOut}>
            <button
              type="submit"
              className="w-full rounded-lg bg-white/10 px-3 py-2 text-left text-sm font-medium text-white/90 hover:bg-white/20"
            >
              Sign out
            </button>
          </form>
        </div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        {/* Mobile top bar + horizontal nav (sidebar only shows md and up) */}
        <header className="flex items-center justify-between border-b border-slate-200 bg-white px-4 py-3 md:hidden print:hidden">
          <span className="flex items-center gap-2 font-semibold text-slate-900">
            <span className="h-2 w-2 rounded-full bg-violet-600" aria-hidden />
            Attendance Admin
          </span>
          <form action={signOut}>
            <button type="submit" className="text-sm text-slate-500 hover:text-slate-900">
              Sign out
            </button>
          </form>
        </header>
        <SideNav
          variant="mobile"
          className="flex gap-1 overflow-x-auto border-b border-slate-200 bg-white px-3 py-2 md:hidden print:hidden"
        />

        <main className="mx-auto w-full max-w-7xl flex-1 px-6 py-8">{children}</main>
      </div>
    </div>
  );
}
