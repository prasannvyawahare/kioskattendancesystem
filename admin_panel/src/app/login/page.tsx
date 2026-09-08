import { signIn } from "./actions";

const ERROR_MESSAGES: Record<string, string> = {
  not_authorized: "This account is not an admin account.",
};

export default function LoginPage({
  searchParams,
}: {
  searchParams: { error?: string };
}) {
  const errorMessage = searchParams.error
    ? (ERROR_MESSAGES[searchParams.error] ?? searchParams.error)
    : null;

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-50 px-4">
      <form
        action={signIn}
        className="w-full max-w-sm space-y-5 rounded-xl border border-slate-200 bg-white p-8 shadow-sm"
      >
        <div>
          <h1 className="text-xl font-semibold text-slate-900">Attendance Admin</h1>
          <p className="mt-1 text-sm text-slate-500">
            Sign in to manage employees and attendance.
          </p>
        </div>

        {errorMessage && (
          <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{errorMessage}</p>
        )}

        <div className="space-y-1">
          <label htmlFor="email" className="text-sm font-medium text-slate-700">
            Email
          </label>
          <input
            id="email"
            name="email"
            type="email"
            required
            autoComplete="email"
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
          />
        </div>

        <div className="space-y-1">
          <label htmlFor="password" className="text-sm font-medium text-slate-700">
            Password
          </label>
          <input
            id="password"
            name="password"
            type="password"
            required
            autoComplete="current-password"
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
          />
        </div>

        <button
          type="submit"
          className="w-full rounded-md bg-slate-900 px-3 py-2 text-sm font-medium text-white hover:bg-slate-800"
        >
          Sign in
        </button>
      </form>
    </main>
  );
}
