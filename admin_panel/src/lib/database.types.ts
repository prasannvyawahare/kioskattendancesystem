// Hand-written types mirroring supabase/migrations/0001_schema.sql, shaped
// to match what `supabase gen types typescript` would produce so the
// generic Supabase client (createBrowserClient<Database> /
// createServerClient<Database>) can resolve Row/Insert/Update types.
// If you install the Supabase CLI later, you can replace this file with
// the real generated output for full accuracy.

export type EmbeddingStatus = "pending" | "processing" | "completed" | "failed";
export type AttendanceEventType = "check_in" | "check_out";
export type ProfileRole = "admin" | "kiosk";
// See supabase/migrations/0025_student_gender.sql.
export type Gender = "male" | "female" | "other";

export interface Database {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string;
          role: ProfileRole;
          full_name: string | null;
          // Class-section scoping for kiosk devices -- see
          // supabase/migrations/0026_kiosk_device_scoping.sql. Both null
          // means unrestricted (sees every class); meaningless for admins.
          assigned_standard: string | null;
          assigned_section: string | null;
          // Admin-panel-assigned device name (e.g. "12th - A Tablet"),
          // distinct from full_name.
          device_label: string | null;
          created_at: string;
        };
        Insert: {
          id: string;
          role: ProfileRole;
          full_name?: string | null;
          assigned_standard?: string | null;
          assigned_section?: string | null;
          device_label?: string | null;
        };
        Update: Partial<{
          role: ProfileRole;
          full_name: string | null;
          assigned_standard: string | null;
          assigned_section: string | null;
          device_label: string | null;
        }>;
        Relationships: [];
      };
      employees: {
        Row: {
          id: string;
          full_name: string;
          email: string | null;
          phone: string | null;
          department: string | null;
          employee_code: string | null;
          // Class/grade and section -- see supabase/migrations/0019_standard_section.sql.
          standard: string | null;
          section: string | null;
          // See supabase/migrations/0025_student_gender.sql.
          gender: Gender | null;
          is_active: boolean;
          embedding_status: EmbeddingStatus;
          // Parent/guardian contacts -- see supabase/migrations/0016_parent_contacts.sql.
          // Captured for present/absent notifications; sending isn't wired
          // up here, just the data capture.
          mother_name: string | null;
          mother_phone: string | null;
          mother_email: string | null;
          father_name: string | null;
          father_phone: string | null;
          father_email: string | null;
          created_at: string;
          created_by: string | null;
        };
        Insert: {
          id?: string;
          full_name: string;
          email?: string | null;
          phone?: string | null;
          department?: string | null;
          employee_code?: string | null;
          standard?: string | null;
          section?: string | null;
          gender?: Gender | null;
          is_active?: boolean;
          embedding_status?: EmbeddingStatus;
          mother_name?: string | null;
          mother_phone?: string | null;
          mother_email?: string | null;
          father_name?: string | null;
          father_phone?: string | null;
          father_email?: string | null;
          created_by?: string | null;
        };
        Update: Partial<{
          full_name: string;
          email: string | null;
          phone: string | null;
          department: string | null;
          employee_code: string | null;
          standard: string | null;
          section: string | null;
          gender: Gender | null;
          is_active: boolean;
          embedding_status: EmbeddingStatus;
          mother_name: string | null;
          mother_phone: string | null;
          mother_email: string | null;
          father_name: string | null;
          father_phone: string | null;
          father_email: string | null;
        }>;
        Relationships: [];
      };
      employee_photos: {
        Row: {
          id: string;
          employee_id: string;
          storage_path: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          employee_id: string;
          storage_path: string;
        };
        Update: Partial<{
          storage_path: string;
        }>;
        Relationships: [];
      };
      face_embeddings: {
        Row: {
          id: string;
          employee_id: string;
          embedding: number[];
          source_photo_id: string | null;
          created_at: string;
        };
        Insert: {
          id?: never; // writes only via record_face_embedding()
        };
        Update: {
          id?: never;
        };
        Relationships: [];
      };
      attendance_logs: {
        Row: {
          id: string;
          employee_id: string;
          event_type: AttendanceEventType;
          event_date: string;
          scanned_at: string;
          confidence: number | null;
          kiosk_id: string | null;
        };
        Insert: {
          id?: never; // writes only via mark_attendance()
        };
        Update: {
          id?: never;
        };
        Relationships: [];
      };
      // Delivery log for supabase/functions/send-attendance-whatsapp --
      // one row per (attendance_logs row, parent contact) send attempt.
      // Written only by the Edge Function via the service-role key. See
      // supabase/migrations/0021_whatsapp_notifications.sql.
      attendance_notification_log: {
        Row: {
          id: string;
          attendance_log_id: string;
          recipient: "mother" | "father";
          channel: "whatsapp" | "sms";
          phone: string;
          status: "sent" | "failed" | "skipped";
          error_message: string | null;
          created_at: string;
        };
        Insert: {
          id?: never; // written only by the Edge Function
        };
        Update: {
          id?: never;
        };
        Relationships: [];
      };
      // Singleton row (id is always `true`) -- admin-managed kiosk config:
      // org name, greeting templates, voice/enrollment toggles, PIN hash.
      // See supabase/migrations/0007_kiosk_enrollment.sql.
      kiosk_settings: {
        Row: {
          id: boolean;
          institution_name: string;
          member_label: string;
          voice_enabled: boolean;
          enrollment_enabled: boolean;
          // Channel for supabase/functions/send-attendance-whatsapp -- see
          // supabase/migrations/0023_notification_channel.sql.
          parent_notification_channel: "disabled" | "whatsapp" | "sms";
          checkin_greeting_template: string;
          checkout_greeting_template: string;
          enrollment_pin_hash: string | null;
          // Kiosk timing knobs -- see supabase/migrations/0015_configurable_timings.sql.
          online_timeout_seconds: number;
          min_scan_gap_minutes: number;
          sync_interval_hours: number;
          refresh_interval_seconds: number;
          // Offline-sync plausibility bounds -- see
          // supabase/migrations/0017_hardening.sql. Not currently surfaced
          // in the settings UI (sensible defaults), but part of the row.
          max_offline_backdate_days: number;
          clock_skew_tolerance_minutes: number;
          updated_at: string;
        };
        Insert: {
          id?: never; // singleton row, seeded by the migration
        };
        Update: Partial<{
          institution_name: string;
          member_label: string;
          voice_enabled: boolean;
          enrollment_enabled: boolean;
          parent_notification_channel: "disabled" | "whatsapp" | "sms";
          checkin_greeting_template: string;
          checkout_greeting_template: string;
          online_timeout_seconds: number;
          min_scan_gap_minutes: number;
          sync_interval_hours: number;
          refresh_interval_seconds: number;
          max_offline_backdate_days: number;
          clock_skew_tolerance_minutes: number;
        }>;
        // enrollment_pin_hash is intentionally not updatable here -- it's
        // only ever written via the set_enrollment_pin() RPC below, so the
        // plaintext PIN never has to be stored client-side.
        Relationships: [];
      };
      // Admin-added non-working dates (on top of every Sunday, which needs
      // no row) -- see supabase/migrations/0024_holidays.sql.
      holidays: {
        Row: {
          id: string;
          holiday_date: string;
          name: string;
          created_at: string;
          created_by: string | null;
        };
        Insert: {
          id?: string;
          holiday_date: string;
          name?: string;
          created_by?: string | null;
        };
        Update: Partial<{
          holiday_date: string;
          name: string;
        }>;
        Relationships: [];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      mark_attendance: {
        Args: {
          p_employee_id: string;
          p_confidence?: number | null;
          p_mode?: "both" | "check_in_only" | "check_out_only";
        };
        Returns: "check_in" | "check_out" | "already_completed";
      };
      // Kiosk-only RPCs (see 0007_kiosk_enrollment.sql) -- included here so
      // TypeScript knows about them, even though only set_enrollment_pin is
      // actually called from the admin panel.
      verify_enrollment_pin: {
        Args: { p_pin: string };
        Returns: boolean;
      };
      enroll_member: {
        Args: { p_pin: string; p_full_name: string; p_code?: string | null; p_group?: string | null };
        Returns: string;
      };
      record_member_photo: {
        Args: { p_employee_id: string; p_storage_path: string };
        Returns: string;
      };
      set_enrollment_pin: {
        Args: { p_pin: string };
        Returns: void;
      };
      // Offline-sync RPCs (see 0013_offline_sync.sql) -- not currently
      // called from the admin panel (kiosk-only), included so the shared
      // client type stays accurate.
      sync_attendance_batch: {
        Args: {
          p_events: Array<{
            employee_id: string;
            event_type: AttendanceEventType;
            event_date: string;
            scanned_at: string;
            confidence?: number | null;
          }>;
        };
        Returns: Array<{
          employee_id: string;
          event_date: string;
          event_type: AttendanceEventType;
          status: "inserted" | "duplicate" | "rejected";
        }>;
      };
      fetch_today_attendance: {
        Args: Record<string, never>;
        Returns: Array<{
          employee_id: string;
          event_type: AttendanceEventType;
          scanned_at: string;
        }>;
      };
    };
    Enums: {
      [_ in never]: never;
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
}

export type Profile = Database["public"]["Tables"]["profiles"]["Row"];
export type Employee = Database["public"]["Tables"]["employees"]["Row"];
export type EmployeePhoto = Database["public"]["Tables"]["employee_photos"]["Row"];
export type AttendanceLog = Database["public"]["Tables"]["attendance_logs"]["Row"];
export type KioskSettings = Database["public"]["Tables"]["kiosk_settings"]["Row"];
export type Holiday = Database["public"]["Tables"]["holidays"]["Row"];
