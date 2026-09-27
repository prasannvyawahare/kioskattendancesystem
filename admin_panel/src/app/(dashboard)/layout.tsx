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
      <aside className="hidden w-64 shrink-0 flex-col overflow-hidden bg-gradient-to-b from-[#4C3494] via-[#5B3FA0] to-[#372767] md:flex print:hidden">
        <div className="flex items-center gap-3 px-6 py-6">
          <span
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-white/15 text-white"
            aria-hidden
          >
            <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.75} className="h-5 w-5">
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
          <span className="font-semibold text-white">Attendance Admin</span>
        </div>
        <SideNav variant="sidebar" className="flex flex-1 flex-col gap-1 px-4 py-2" />
        <div className="mx-4 mb-4 rounded-xl bg-white/10 p-3">
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
