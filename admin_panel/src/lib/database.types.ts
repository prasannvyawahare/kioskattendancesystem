// Hand-written types mirroring supabase/migrations/0001_schema.sql, shaped
// to match what `supabase gen types typescript` would produce so the
// generic Supabase client (createBrowserClient<Database> /
// createServerClient<Database>) can resolve Row/Insert/Update types.
// If you install the Supabase CLI later, you can replace this file with
// the real generated output for full accuracy.

export type EmbeddingStatus = "pending" | "processing" | "completed" | "failed";
export type AttendanceEventType = "check_in" | "check_out";
export type ProfileRole = "admin" | "kiosk";

export interface Database {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string;
          role: ProfileRole;
          full_name: string | null;
          created_at: string;
        };
        Insert: {
          id: string;
          role: ProfileRole;
          full_name?: string | null;
        };
        Update: Partial<{
          role: ProfileRole;
          full_name: string | null;
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
          is_active: boolean;
          embedding_status: EmbeddingStatus;
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
          is_active?: boolean;
          embedding_status?: EmbeddingStatus;
          created_by?: string | null;
        };
        Update: Partial<{
          full_name: string;
          email: string | null;
          phone: string | null;
          department: string | null;
          employee_code: string | null;
          is_active: boolean;
          embedding_status: EmbeddingStatus;
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
          checkin_greeting_template: string;
          checkout_greeting_template: string;
          enrollment_pin_hash: string | null;
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
          checkin_greeting_template: string;
          checkout_greeting_template: string;
        }>;
        // enrollment_pin_hash is intentionally not updatable here -- it's
        // only ever written via the set_enrollment_pin() RPC below, so the
        // plaintext PIN never has to be stored client-side.
        Relationships: [];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      mark_attendance: {
        Args: { p_employee_id: string; p_confidence?: number | null };
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
    };
    Enums: {
      [_ in never]: never;
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
}

export type Employee = Database["public"]["Tables"]["employees"]["Row"];
export type EmployeePhoto = Database["public"]["Tables"]["employee_photos"]["Row"];
export type AttendanceLog = Database["public"]["Tables"]["attendance_logs"]["Row"];
export type KioskSettings = Database["public"]["Tables"]["kiosk_settings"]["Row"];
