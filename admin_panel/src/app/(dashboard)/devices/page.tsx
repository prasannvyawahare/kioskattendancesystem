import { createAdminClient } from "@/lib/supabase/admin";
import { AddDeviceDialog } from "./AddDeviceDialog";
import { DeviceRow, type DeviceListItem } from "./DeviceRow";

export default async function DevicesPage({
  searchParams,
}: {
  searchParams: { error?: string; saved?: string };
}) {
  let devices: DeviceListItem[] = [];
  let loadError: string | null = null;

  try {
    const supabaseAdmin = createAdminClient();
    const { data: profiles, error } = await supabaseAdmin
      .from("profiles")
      .select("id, device_label, full_name, assigned_standard, assigned_section, created_at")
      .eq("role", "kiosk")
      .order("created_at", { ascending: false });
    if (error) throw error;

    devices = await Promise.all(
      (profiles ?? []).map(async (profile) => {
        const { data } = await supabaseAdmin.auth.admin.getUserById(profile.id);
        return {
          id: profile.id,
          device_label: profile.device_label,
          full_name: profile.full_name,
          assigned_standard: profile.assigned_standard,
          assigned_section: profile.assigned_section,
          email: data.user?.email ?? null,
          lastSignInAt: data.user?.last_sign_in_at ?? null,
        };
      }),
    );
  } catch (err) {
    loadError = err instanceof Error ? err.message : "Could not load devices";
  }

  return (
    <div className="max-w-3xl space-y-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-lg font-semibold text-slate-900">Kiosk devices</h1>
          <p className="mt-1 text-sm text-slate-500">
            One device per physical tablet. Scope a device to a standard/section so that
            tablet&apos;s camera screen and on-device enrollment only ever see students in that
            class -- leave both blank for a device that should see everyone (e.g. a front-desk
            kiosk).
          </p>
        </div>
        <AddDeviceDialog />
      </div>

      {searchParams.error && (
        <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{searchParams.error}</p>
      )}
      {searchParams.saved && (
        <p className="rounded-md bg-emerald-50 px-3 py-2 text-sm text-emerald-700">Saved.</p>
      )}

      {loadError && (
        <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
          {loadError}
          {loadError.includes("SUPABASE_SERVICE_ROLE_KEY") ? null : (
            <>
              {" "}
              If this mentions the service role key, see <code>.env.local.example</code>.
            </>
          )}
        </p>
      )}

      <div className="rounded-xl border border-slate-200 bg-white p-4">
        {devices.length === 0 ? (
          <p className="text-sm text-slate-400">No kiosk devices yet.</p>
        ) : (
          <ul className="divide-y divide-slate-100">
            {devices.map((device) => (
              <DeviceRow key={device.id} device={device} />
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
