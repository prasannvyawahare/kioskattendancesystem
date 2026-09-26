import { RegisterEmployeeForm } from "./register-employee-form";

export default function NewEmployeePage({
  searchParams,
}: {
  searchParams: { error?: string };
}) {
  return (
    <div className="max-w-2xl">
      <h1 className="text-lg font-semibold text-slate-900">Register student</h1>
      <p className="mt-1 text-sm text-slate-500">
        Capture 3-5 photos (front, left, right) for reliable kiosk recognition. The kiosk
        computes face embeddings itself once it syncs these photos — recognition won&apos;t work
        until the student&apos;s status shows &quot;completed&quot;.
      </p>

      {searchParams.error && (
        <p className="mt-4 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
          {searchParams.error}
        </p>
      )}

      <div className="mt-6">
        <RegisterEmployeeForm />
      </div>
    </div>
  );
}
