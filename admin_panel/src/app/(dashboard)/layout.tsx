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
    <div className="flex min-h-screen bg-slate-50">
      {/* Desktop sidebar */}
      <aside className="hidden w-60 shrink-0 flex-col border-r border-slate-200 bg-white md:flex print:hidden">
        <div className="flex items-center gap-2 border-b border-slate-200 px-5 py-5">
          <span className="h-2 w-2 rounded-full bg-indigo-600" aria-hidden />
          <span className="font-semibold text-slate-900">Attendance Admin</span>
        </div>
        <SideNav className="flex flex-1 flex-col gap-1 px-3 py-4" />
        <div className="border-t border-slate-200 p-3">
          <p className="truncate px-3 pb-2 text-xs text-slate-400">{user.email}</p>
          <form action={signOut}>
            <button
              type="submit"
              className="w-full rounded-lg px-3 py-2 text-left text-sm font-medium text-slate-600 hover:bg-slate-100 hover:text-slate-900"
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
            <span className="h-2 w-2 rounded-full bg-indigo-600" aria-hidden />
            Attendance Admin
          </span>
          <form action={signOut}>
            <button type="submit" className="text-sm text-slate-500 hover:text-slate-900">
              Sign out
            </button>
          </form>
        </header>
        <SideNav className="flex gap-1 overflow-x-auto border-b border-slate-200 bg-white px-3 py-2 md:hidden print:hidden" />

        <main className="mx-auto w-full max-w-6xl flex-1 px-6 py-8">{children}</main>
      </div>
    </div>
  );
}
