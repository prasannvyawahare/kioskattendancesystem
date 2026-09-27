import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { toggleActive, resetEmbeddings } from "../actions";
import { DeleteEmployeeButton } from "./DeleteEmployeeButton";
import { AutoRefresh } from "@/components/AutoRefresh";
import { eventTypeLabel } from "@/lib/attendance-status";

export default async function EmployeeDetailPage({
  params,
  searchParams,
}: {
  params: { id: string };
  searchParams: { error?: string };
}) {
  const supabase = createClient();

  const { data: employee } = await supabase
    .from("employees")
    .select("*")
    .eq("id", params.id)
    .single();

  if (!employee) notFound();

  // Independent queries -- run concurrently rather than paying two
  // sequential Supabase round-trips back to back.
  const [{ data: photoRows }, { data: attendance }] = await Promise.all([
    supabase.from("employee_photos").select("id, storage_path").eq("employee_id", employee.id),
    supabase
      .from("attendance_logs")
      .select("event_type, event_date, scanned_at")
      .eq("employee_id", employee.id)
      .order("scanned_at", { ascending: false })
      .limit(20),
  ]);

  const photos = await Promise.all(
    (photoRows ?? []).map(async (photo) => {
      const { data } = await supabase.storage
        .from("employee-photos")
        .createSignedUrl(photo.storage_path, 3600);
      return { id: photo.id, url: data?.signedUrl };
    }),
  );

  return (
    <div className="space-y-8">
      <AutoRefresh />
      {searchParams.error && (
        <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{searchParams.error}</p>
      )}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-lg font-semibold text-slate-900">{employee.full_name}</h1>
          <p className="text-sm text-slate-500">
            {employee.employee_code ?? "No code"} · {employee.department ?? "No department"} ·{" "}
            {employee.standard ? `Standard ${employee.standard}` : "No standard"}
            {employee.section ? ` - ${employee.section}` : ""}
          </p>
        </div>
        <div className="flex items-center gap-4">
          <Link
            href={`/employees/${employee.id}/edit`}
            className="text-sm font-medium text-slate-600 hover:text-slate-900"
          >
            Edit
          </Link>
          <DeleteEmployeeButton employeeId={employee.id} fullName={employee.full_name} />
          <Link href="/employees" className="text-sm text-slate-500 hover:text-slate-900">
            Back to students
          </Link>
        </div>
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
          The kiosk computes embeddings from these photos on its own sync cycle — this student
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
          <h2 className="text-sm font-medium text-slate-900">Student</h2>
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
        <h2 className="text-sm font-medium text-slate-900">Parent / guardian details</h2>
        <div className="mt-3 grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">Mother</p>
            <dl className="mt-2 space-y-1 text-sm">
              <div className="flex justify-between gap-3">
                <dt className="text-slate-500">Name</dt>
                <dd className="text-slate-900">{employee.mother_name ?? "-"}</dd>
              </div>
              <div className="flex justify-between gap-3">
                <dt className="text-slate-500">Phone</dt>
                <dd className="text-slate-900">{employee.mother_phone ?? "-"}</dd>
              </div>
              <div className="flex justify-between gap-3">
                <dt className="text-slate-500">Email</dt>
                <dd className="text-slate-900">{employee.mother_email ?? "-"}</dd>
              </div>
            </dl>
          </div>
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">Father</p>
            <dl className="mt-2 space-y-1 text-sm">
              <div className="flex justify-between gap-3">
                <dt className="text-slate-500">Name</dt>
                <dd className="text-slate-900">{employee.father_name ?? "-"}</dd>
              </div>
              <div className="flex justify-between gap-3">
                <dt className="text-slate-500">Phone</dt>
                <dd className="text-slate-900">{employee.father_phone ?? "-"}</dd>
              </div>
              <div className="flex justify-between gap-3">
                <dt className="text-slate-500">Email</dt>
                <dd className="text-slate-900">{employee.father_email ?? "-"}</dd>
              </div>
            </dl>
          </div>
        </div>
      </section>

      <section className="rounded-xl border border-slate-200 bg-white p-4">
        <h2 className="text-sm font-medium text-slate-900">Recent attendance</h2>
        <ul className="mt-3 divide-y divide-slate-100 text-sm">
          {attendance?.map((row, i) => (
            <li key={i} className="flex items-center justify-between py-2">
              <span className="text-slate-700">{eventTypeLabel(row.event_type)}</span>
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
