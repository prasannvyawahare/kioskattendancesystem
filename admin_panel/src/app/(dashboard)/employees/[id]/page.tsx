import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { toggleActive, resetEmbeddings } from "../actions";

export default async function EmployeeDetailPage({ params }: { params: { id: string } }) {
  const supabase = createClient();

  const { data: employee } = await supabase
    .from("employees")
    .select("*")
    .eq("id", params.id)
    .single();

  if (!employee) notFound();

  const { data: photoRows } = await supabase
    .from("employee_photos")
    .select("id, storage_path")
    .eq("employee_id", employee.id);

  const photos = await Promise.all(
    (photoRows ?? []).map(async (photo) => {
      const { data } = await supabase.storage
        .from("employee-photos")
        .createSignedUrl(photo.storage_path, 300);
      return { id: photo.id, url: data?.signedUrl };
    }),
  );

  const { data: attendance } = await supabase
    .from("attendance_logs")
    .select("event_type, event_date, scanned_at")
    .eq("employee_id", employee.id)
    .order("scanned_at", { ascending: false })
    .limit(20);

  return (
    <div className="space-y-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-lg font-semibold text-slate-900">{employee.full_name}</h1>
          <p className="text-sm text-slate-500">
            {employee.employee_code ?? "No code"} · {employee.department ?? "No department"}
          </p>
        </div>
        <Link href="/employees" className="text-sm text-slate-500 hover:text-slate-900">
          Back to employees
        </Link>
      </div>

      <section className="rounded-xl border border-slate-200 bg-white p-4">
        <h2 className="text-sm font-medium text-slate-900">Recognition status</h2>
        <div className="mt-2 flex items-center gap-3">
          <span className="rounded-full bg-slate-100 px-2 py-1 text-xs font-medium text-slate-700">
            {employee.embedding_status}
          </span>
          {employee.embedding_status !== "pending" && (
            <form action={resetEmbeddings.bind(null, employee.id)}>
              <button type="submit" className="text-xs font-medium text-slate-600 underline">
                Re-run enrollment
              </button>
            </form>
          )}
        </div>
        <p className="mt-2 text-xs text-slate-500">
          The kiosk computes embeddings from these photos on its own sync cycle — this employee
          becomes recognizable once status reaches &quot;completed&quot;.
        </p>

        <div className="mt-4 flex flex-wrap gap-3">
          {photos.map((photo) =>
            photo.url ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                key={photo.id}
                src={photo.url}
                alt="Enrollment"
                className="h-24 w-24 rounded-md object-cover"
              />
            ) : null,
          )}
        </div>
      </section>

      <section className="rounded-xl border border-slate-200 bg-white p-4">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-medium text-slate-900">Employee</h2>
          <form action={toggleActive.bind(null, employee.id, !employee.is_active)}>
            <button type="submit" className="text-xs font-medium text-slate-600 underline">
              {employee.is_active ? "Deactivate" : "Reactivate"}
            </button>
          </form>
        </div>
        <dl className="mt-3 grid grid-cols-2 gap-3 text-sm">
          <div>
            <dt className="text-slate-500">Email</dt>
            <dd className="text-slate-900">{employee.email ?? "-"}</dd>
          </div>
          <div>
            <dt className="text-slate-500">Phone</dt>
            <dd className="text-slate-900">{employee.phone ?? "-"}</dd>
          </div>
        </dl>
      </section>

      <section className="rounded-xl border border-slate-200 bg-white p-4">
        <h2 className="text-sm font-medium text-slate-900">Recent attendance</h2>
        <ul className="mt-3 divide-y divide-slate-100 text-sm">
          {attendance?.map((row, i) => (
            <li key={i} className="flex items-center justify-between py-2">
              <span className="capitalize text-slate-700">{row.event_type.replace("_", " ")}</span>
              <span className="text-slate-500">{new Date(row.scanned_at).toLocaleString()}</span>
            </li>
          ))}
          {attendance?.length === 0 && (
            <p className="py-4 text-center text-slate-400">No attendance yet.</p>
          )}
        </ul>
      </section>
    </div>
  );
}
