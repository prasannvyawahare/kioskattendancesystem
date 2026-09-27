import { signIn } from "./actions";

const ERROR_MESSAGES: Record<string, string> = {
  not_authorized: "This account is not an admin account.",
};

const FEATURES: { title: string; description: string; icon: React.ReactNode }[] = [
  {
    title: "Face-recognition check-in",
    description: "Students are marked present the moment the kiosk camera recognizes them.",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.75} className="h-5 w-5">
        <path
          d="M4.5 8V6a1.5 1.5 0 011.5-1.5h2M19.5 8V6A1.5 1.5 0 0018 4.5h-2M4.5 16v2A1.5 1.5 0 006 19.5h2M19.5 16v2a1.5 1.5 0 01-1.5 1.5h-2"
          stroke="currentColor"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
        <circle cx="12" cy="10.5" r="2.5" stroke="currentColor" />
        <path d="M8 16c.8-1.8 2.2-2.7 4-2.7s3.2.9 4 2.7" stroke="currentColor" strokeLinecap="round" />
      </svg>
    ),
  },
  {
    title: "Instant parent alerts",
    description: "Every check-in and check-out sends a WhatsApp or SMS ping to parents automatically.",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.75} className="h-5 w-5">
        <path
          d="M4 19l1.4-3.6A7.5 7.5 0 1112 19.5a7.4 7.4 0 01-3.4-.8L4 19z"
          stroke="currentColor"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
        <path d="M9 10.5h6M9 13.5h4" stroke="currentColor" strokeLinecap="round" />
      </svg>
    ),
  },
  {
    title: "Real-time insights",
    description: "Live attendance feed, monthly registers, and CSV exports without lifting a finger.",
    icon: (
      <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.75} className="h-5 w-5">
        <path d="M4.5 19.5v-6M10 19.5v-10M15.5 19.5v-4M21 19.5v-13" stroke="currentColor" strokeLinecap="round" />
      </svg>
    ),
  },
];

export default function LoginPage({
  searchParams,
}: {
  searchParams: { error?: string };
}) {
  const errorMessage = searchParams.error
    ? (ERROR_MESSAGES[searchParams.error] ?? searchParams.error)
    : null;

  return (
    <main className="flex min-h-screen bg-[#F3F4FB]">
      {/* Left: highlighted-feature panel, hidden on small screens */}
      <div className="relative hidden w-1/2 flex-col justify-between overflow-hidden bg-gradient-to-br from-[#4C3494] via-[#5B3FA0] to-[#2E2158] p-12 text-white lg:flex">
        <div className="pointer-events-none absolute inset-0 overflow-hidden" aria-hidden>
          <div className="absolute -left-24 -top-24 h-72 w-72 rounded-full bg-white/10 blur-3xl" />
          <div className="absolute -right-16 top-1/3 h-64 w-64 rounded-full bg-fuchsia-400/10 blur-3xl" />
          <div className="absolute -bottom-28 left-1/4 h-72 w-72 rounded-full bg-indigo-300/10 blur-3xl" />
        </div>

        <div className="relative flex items-center gap-3">
          <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-white text-violet-700 shadow-md shadow-black/10">
            <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.75} className="h-6 w-6">
              <path d="M4 6.5l8-3 8 3-8 3-8-3z" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" />
              <path
                d="M7 8.5v5c0 1.5 2.2 2.5 5 2.5s5-1 5-2.5v-5"
                stroke="currentColor"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
          </span>
          <span className="font-semibold">Attendance Admin</span>
        </div>

        <div className="relative space-y-8">
          <div className="space-y-3">
            <h2 className="text-3xl font-semibold leading-tight">
              Attendance that runs itself, so you can focus on students.
            </h2>
            <p className="text-sm text-white/70">
              One dashboard to enroll students, watch the kiosk feed live, and keep parents in the
              loop automatically.
            </p>
          </div>

          <ul className="space-y-5">
            {FEATURES.map((feature) => (
              <li key={feature.title} className="flex items-start gap-4">
                <span className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-white/15">
                  {feature.icon}
                </span>
                <div>
                  <p className="font-medium">{feature.title}</p>
                  <p className="mt-0.5 text-sm text-white/65">{feature.description}</p>
                </div>
              </li>
            ))}
          </ul>
        </div>

        <p className="relative text-xs text-white/40">Kiosk console · shared Supabase backend</p>
      </div>

      {/* Right: login form */}
      <div className="flex w-full flex-1 items-center justify-center px-6 py-12 lg:w-1/2">
        <form action={signIn} className="w-full max-w-sm space-y-6">
          <div className="mb-2 flex items-center gap-3 lg:hidden">
            <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-violet-600 text-white">
              <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.75} className="h-5 w-5">
                <path d="M4 6.5l8-3 8 3-8 3-8-3z" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" />
                <path
                  d="M7 8.5v5c0 1.5 2.2 2.5 5 2.5s5-1 5-2.5v-5"
                  stroke="currentColor"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                />
              </svg>
            </span>
            <span className="font-semibold text-slate-900">Attendance Admin</span>
          </div>

          <div>
            <h1 className="text-2xl font-semibold text-slate-900">Welcome back</h1>
            <p className="mt-1 text-sm text-slate-500">
              Sign in to manage students and attendance.
            </p>
          </div>

          {errorMessage && (
            <p className="rounded-lg bg-rose-50 px-3 py-2 text-sm text-rose-700">{errorMessage}</p>
          )}

          <div className="space-y-4">
            <div className="space-y-1.5">
              <label htmlFor="email" className="text-sm font-medium text-slate-700">
                Email address
              </label>
              <div className="relative">
                <span className="pointer-events-none absolute inset-y-0 left-3 flex items-center text-slate-400">
                  <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.75} className="h-4 w-4">
                    <rect x="3.5" y="5.5" width="17" height="13" rx="2" stroke="currentColor" />
                    <path d="M4.5 7l7.5 6 7.5-6" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                </span>
                <input
                  id="email"
                  name="email"
                  type="email"
                  required
                  autoComplete="email"
                  placeholder="you@school.edu"
                  className="w-full rounded-xl border border-slate-200 bg-slate-50 py-2.5 pl-10 pr-3 text-sm text-slate-900 outline-none transition-colors placeholder:text-slate-400 focus:border-violet-500 focus:bg-white focus:ring-2 focus:ring-violet-100"
                />
              </div>
            </div>

            <div className="space-y-1.5">
              <label htmlFor="password" className="text-sm font-medium text-slate-700">
                Password
              </label>
              <div className="relative">
                <span className="pointer-events-none absolute inset-y-0 left-3 flex items-center text-slate-400">
                  <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.75} className="h-4 w-4">
                    <rect x="5" y="10.5" width="14" height="9" rx="2" stroke="currentColor" />
                    <path d="M8 10.5V7.5a4 4 0 018 0v3" stroke="currentColor" strokeLinecap="round" />
                  </svg>
                </span>
                <input
                  id="password"
                  name="password"
                  type="password"
                  required
                  autoComplete="current-password"
                  placeholder="••••••••"
                  className="w-full rounded-xl border border-slate-200 bg-slate-50 py-2.5 pl-10 pr-3 text-sm text-slate-900 outline-none transition-colors placeholder:text-slate-400 focus:border-violet-500 focus:bg-white focus:ring-2 focus:ring-violet-100"
                />
              </div>
            </div>
          </div>

          <button
            type="submit"
            className="w-full rounded-xl bg-gradient-to-r from-violet-600 to-indigo-600 px-3 py-2.5 text-sm font-semibold text-white shadow-md shadow-violet-500/25 transition-opacity hover:opacity-90"
          >
            Sign in
          </button>

          <p className="text-center text-xs text-slate-400">
            Admin access only · contact your institution to get an account.
          </p>
        </form>
      </div>
    </main>
  );
}
