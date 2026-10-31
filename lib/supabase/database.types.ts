// Schema snapshot based on the checked-in migrations. Regenerate from the local
// Supabase database with `pnpm db:types` after applying migrations 001-025.
// Relationship metadata mirrors the migration foreign keys until the local
// Supabase project is available for CLI generation.
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

type Relationship = { foreignKeyName: string; columns: string[]; isOneToOne: boolean; referencedRelation: string; referencedColumns: string[] };
type Table<Row, Relations extends Relationship[] = []> = {
  Row: Row;
  Insert: Partial<Row>;
  Update: Partial<Row>;
  Relationships: Relations;
};

export type Database = {
  public: {
    Tables: {
      organizations: Table<{ id: string; name: string; slug: string; legal_name: string | null; timezone: string; currency: string; status: Database["public"]["Enums"]["record_status"]; ai_monthly_budget_usd: number | null; ai_budget_started_at: string | null; created_at: string; updated_at: string }>;
      profiles: Table<{ id: string; full_name: string; avatar_url: string | null; phone: string | null; created_at: string; updated_at: string }>;
      org_members: Table<{ organization_id: string; user_id: string; role: Database["public"]["Enums"]["member_role"]; title: string | null; status: "invited" | "active" | "suspended"; joined_at: string | null; created_at: string }, [{ foreignKeyName: "org_members_organization_id_fkey"; columns: ["organization_id"]; isOneToOne: false; referencedRelation: "organizations"; referencedColumns: ["id"] }] >;
      roles: Table<{ id: string; organization_id: string; name: string; is_system: boolean; permissions: Json; created_at: string }>;
      role_assignments: Table<{ organization_id: string; user_id: string; role_id: string }>;
      clients: Table<{ id: string; organization_id: string; name: string; industry: string | null; website: string | null; health: "healthy" | "needs_attention" | "at_risk" | "churned"; monthly_value: number; owner_id: string | null; notes: string | null; status: Database["public"]["Enums"]["record_status"]; created_at: string; updated_at: string }>;
      contacts: Table<{ id: string; organization_id: string; client_id: string | null; first_name: string; last_name: string | null; email: string | null; phone: string | null; job_title: string | null; is_primary: boolean; created_at: string; updated_at: string }>;
      leads: Table<{ id: string; organization_id: string; company_name: string; contact_name: string | null; email: string | null; phone: string | null; source: string | null; stage: Database["public"]["Enums"]["lead_stage"]; estimated_value: number; probability: number; owner_id: string | null; next_action: string | null; next_action_at: string | null; converted_client_id: string | null; created_at: string; updated_at: string }>;
      deals: Table<{ id: string; organization_id: string; lead_id: string | null; client_id: string | null; name: string; stage: Database["public"]["Enums"]["lead_stage"]; value: number; expected_close_date: string | null; owner_id: string | null; created_at: string; updated_at: string }>;
      projects: Table<{ id: string; organization_id: string; client_id: string | null; name: string; description: string | null; status: Database["public"]["Enums"]["project_status"]; priority: "low" | "medium" | "high" | "urgent"; start_date: string | null; due_date: string | null; budget: number; owner_id: string | null; created_by: string | null; created_at: string; updated_at: string }, [{ foreignKeyName: "projects_organization_id_client_id_fkey"; columns: ["organization_id", "client_id"]; isOneToOne: false; referencedRelation: "clients"; referencedColumns: ["organization_id", "id"] }] >;
      tasks: Table<{ id: string; organization_id: string; project_id: string | null; client_id: string | null; title: string; description: string | null; status: Database["public"]["Enums"]["task_status"]; priority: "low" | "medium" | "high" | "urgent"; assignee_id: string | null; due_at: string | null; completed_at: string | null; created_by: string | null; created_at: string; updated_at: string }, [{ foreignKeyName: "tasks_organization_id_project_id_fkey"; columns: ["organization_id", "project_id"]; isOneToOne: false; referencedRelation: "projects"; referencedColumns: ["organization_id", "id"] }, { foreignKeyName: "tasks_organization_id_client_id_fkey"; columns: ["organization_id", "client_id"]; isOneToOne: false; referencedRelation: "clients"; referencedColumns: ["organization_id", "id"] }] >;
      task_comments: Table<{ id: string; organization_id: string; task_id: string; author_id: string | null; body: string; created_at: string }, [{ foreignKeyName: "task_comments_organization_id_task_id_fkey"; columns: ["organization_id", "task_id"]; isOneToOne: false; referencedRelation: "tasks"; referencedColumns: ["organization_id", "id"] }] >;
      content_items: Table<{ id: string; organization_id: string; client_id: string | null; project_id: string | null; title: string; format: string; channel: string | null; status: Database["public"]["Enums"]["content_status"]; caption: string | null; scheduled_at: string | null; published_at: string | null; owner_id: string | null; created_at: string; updated_at: string }>;
      content_reviews: Table<{ id: string; organization_id: string; content_item_id: string; reviewer_id: string; decision: "comment" | "approved" | "changes_requested"; feedback: string; created_at: string }, [{ foreignKeyName: "content_reviews_organization_id_content_item_id_fkey"; columns: ["organization_id", "content_item_id"]; isOneToOne: false; referencedRelation: "content_items"; referencedColumns: ["organization_id", "id"] }] >;
      team_performance_reviews: Table<{ id: string; organization_id: string; member_id: string; author_id: string | null; updated_by: string | null; period_start: string; delivery_score: number; communication_score: number; ownership_score: number; client_care_score: number; highlights: string; growth_focus: string; manager_notes: string; created_at: string; updated_at: string }, [{ foreignKeyName: "team_performance_reviews_organization_id_member_id_fkey"; columns: ["organization_id", "member_id"]; isOneToOne: false; referencedRelation: "org_members"; referencedColumns: ["organization_id", "user_id"] }] >;
      invoices: Table<{ id: string; organization_id: string; client_id: string; invoice_number: string; status: Database["public"]["Enums"]["invoice_status"]; currency: string; subtotal: number; tax: number; total: number; credit_total: number; amount_paid: number; issue_date: string | null; due_date: string | null; paid_at: string | null; created_at: string; updated_at: string }, [{ foreignKeyName: "invoices_organization_id_client_id_fkey"; columns: ["organization_id", "client_id"]; isOneToOne: false; referencedRelation: "clients"; referencedColumns: ["organization_id", "id"] }] >;
      invoice_credits: Table<{ id: string; organization_id: string; invoice_id: string; credit_number: string; amount: number; reason: string; issued_at: string; recorded_by: string | null; created_at: string }, [{ foreignKeyName: "invoice_credits_organization_id_invoice_id_fkey"; columns: ["organization_id", "invoice_id"]; isOneToOne: false; referencedRelation: "invoices"; referencedColumns: ["organization_id", "id"] }] >;
      invoice_refunds: Table<{ id: string; organization_id: string; invoice_id: string; payment_id: string; amount: number; reason: string; refunded_at: string; recorded_by: string | null; created_at: string }, [{ foreignKeyName: "invoice_refunds_organization_id_invoice_id_fkey"; columns: ["organization_id", "invoice_id"]; isOneToOne: false; referencedRelation: "invoices"; referencedColumns: ["organization_id", "id"] }, { foreignKeyName: "invoice_refunds_organization_id_invoice_id_payment_id_fkey"; columns: ["organization_id", "invoice_id", "payment_id"]; isOneToOne: false; referencedRelation: "invoice_payments"; referencedColumns: ["organization_id", "invoice_id", "id"] }] >;
      organization_files: Table<{ id: string; organization_id: string; storage_path: string; original_filename: string; mime_type: string; size_bytes: number; uploaded_by: string | null; created_at: string }>;
      invoice_items: Table<{ id: string; organization_id: string; invoice_id: string; description: string; quantity: number; unit_price: number; line_total: number; created_at: string; updated_at: string }, [{ foreignKeyName: "invoice_items_organization_id_invoice_id_fkey"; columns: ["organization_id", "invoice_id"]; isOneToOne: false; referencedRelation: "invoices"; referencedColumns: ["organization_id", "id"] }] >;
      expenses: Table<{ id: string; organization_id: string; project_id: string | null; description: string; category: string; amount: number; currency: string; spent_on: string; created_by: string | null; created_at: string }>;
      automation_rules: Table<{ id: string; organization_id: string; name: string; description: string | null; trigger_type: string; trigger_config: Json; action_config: Json; is_enabled: boolean; created_by: string | null; next_run_at: string | null; created_at: string; updated_at: string }>;
      automation_runs: Table<{ id: string; organization_id: string; rule_id: string | null; status: "queued" | "running" | "succeeded" | "failed" | "skipped"; trigger_payload: Json; result: Json | null; error_message: string | null; started_at: string | null; finished_at: string | null; actor_id: string | null; source: "manual" | "scheduled" | "event"; idempotency_key: string; attempt_count: number; max_attempts: number; created_at: string }>;
      automation_run_attempts: Table<{ id: string; organization_id: string; run_id: string; attempt_number: number; idempotency_key: string; actor_id: string | null; source: "manual" | "scheduled" | "event"; status: "running" | "succeeded" | "failed"; result: Json | null; error_message: string | null; started_at: string; finished_at: string | null }, [{ foreignKeyName: "automation_run_attempts_organization_id_run_id_fkey"; columns: ["organization_id", "run_id"]; isOneToOne: false; referencedRelation: "automation_runs"; referencedColumns: ["organization_id", "id"] }] >;
      integrations: Table<{ id: string; organization_id: string; provider: string; display_name: string; status: "disconnected" | "connected" | "error" | "reauthorization_required"; external_account_id: string | null; secret_reference: string | null; scopes: string[]; last_synced_at: string | null; created_at: string; updated_at: string }>;
      integration_secrets: Table<{ id: string; organization_id: string; integration_id: string; encrypted_credentials: string; key_version: number; expires_at: string | null; updated_at: string }>;
      ai_conversations: Table<{ id: string; organization_id: string; user_id: string; title: string; context: Json; created_at: string; updated_at: string }>;
      ai_messages: Table<{ id: string; organization_id: string; conversation_id: string; role: "user" | "assistant" | "tool"; content: string; model: string | null; usage: Json | null; created_at: string }>;
      ai_action_drafts: Table<{ id: string; organization_id: string; user_id: string; action_type: "create_task"; title: string; description: string; priority: "low" | "medium" | "high" | "urgent"; suggested_due_date: string | null; model: string | null; usage: Json | null; status: "pending" | "confirmed" | "cancelled"; task_id: string | null; expires_at: string; confirmed_at: string | null; created_at: string }, [{ foreignKeyName: "ai_action_drafts_task_id_fkey"; columns: ["task_id"]; isOneToOne: false; referencedRelation: "tasks"; referencedColumns: ["id"] }] >;
      ai_usage_events: Table<{ id: string; organization_id: string; user_id: string; request_type: "assistant_reply" | "task_draft"; model: string; status: "reserved" | "completed" | "failed"; input_tokens: number; output_tokens: number; reserved_usd: number; actual_cost_usd: number | null; created_at: string; completed_at: string | null; expires_at: string }, [{ foreignKeyName: "ai_usage_events_organization_id_fkey"; columns: ["organization_id"]; isOneToOne: false; referencedRelation: "organizations"; referencedColumns: ["id"] }] >;
      audit_logs: Table<{ id: number; organization_id: string; actor_id: string | null; action: string; entity_type: string; entity_id: string | null; changes: Json; request_id: string | null; created_at: string }>;
      invoice_payments: Table<{ id: string; organization_id: string; invoice_id: string; amount: number; currency: string; paid_at: string; method: "bank_transfer" | "cash" | "card" | "cheque" | "other"; provider_reference: string | null; recorded_by: string | null; created_at: string }>;
      org_invitations: Table<{ id: string; organization_id: string; email: string; user_id: string; role: "admin" | "manager" | "member"; status: "pending" | "accepted" | "revoked"; invited_by: string; created_at: string; accepted_at: string | null }>;
    };
    Views: Record<string, never>;
    Functions: {
      is_org_member: { Args: { target_org: string }; Returns: boolean };
      has_org_permission: { Args: { target_org: string; permission_key: string }; Returns: boolean };
      create_organization: { Args: { org_name: string; org_slug: string }; Returns: string };
      create_client_with_contact: { Args: { target_org: string; client_name: string; client_industry?: string | null; client_website?: string | null; client_monthly_value?: number; contact_first_name?: string | null; contact_last_name?: string | null; contact_email?: string | null; contact_phone?: string | null }; Returns: string };
      sales_summary: { Args: { target_org: string }; Returns: { open_lead_count: number; pipeline_value: number; proposal_count: number }[] };
      finance_summary: { Args: { target_org: string }; Returns: { currency: string; monthly_revenue: number; receivables: number; monthly_expenses: number; estimated_profit: number }[] };
      finance_monthly_trend: { Args: { target_org: string; month_count?: number }; Returns: { currency: string; month_start: string; revenue: number; expenses: number; net_cash: number }[] };
      receivables_aging: { Args: { target_org: string }; Returns: { currency: string; bucket: string; invoice_count: number; amount: number }[] };
      report_summary: { Args: { target_org: string; days_back?: number }; Returns: { period_start: string; open_leads: number; won_leads: number; lost_leads: number; active_clients: number; healthy_clients: number; needs_attention_clients: number; at_risk_clients: number; churned_clients: number; completed_tasks_in_period: number; completed_tasks_with_due_date: number; on_time_tasks_in_period: number; open_tasks: number; blocked_tasks: number; active_internal_members: number }[] };
      report_team_workload: { Args: { target_org: string }; Returns: { member_id: string; full_name: string; open_tasks: number; blocked_tasks: number; overdue_tasks: number }[] };
      confirm_ai_task_draft: { Args: { target_org: string; draft_id: string; final_title: string; final_description?: string | null; final_priority?: string | null; final_due_date?: string | null; selected_project?: string | null; selected_assignee?: string | null }; Returns: string };
      cancel_ai_task_draft: { Args: { target_org: string; draft_id: string }; Returns: boolean };
      reserve_ai_budget: { Args: { target_org: string; target_user: string; request_id: string; request_type: string; request_model: string; estimated_cost_usd: number | null }; Returns: boolean };
      settle_ai_budget: { Args: { request_id: string; target_user: string; input_count: number; output_count: number; actual_cost: number | null }; Returns: boolean };
      release_ai_budget: { Args: { request_id: string; target_user: string }; Returns: boolean };
      set_org_ai_monthly_budget: { Args: { target_org: string; budget_usd: number | null }; Returns: boolean };
      ai_budget_status: { Args: { target_org: string }; Returns: { budget_usd: number | null; spent_usd: number; reserved_usd: number }[] };
      log_organization_data_export: { Args: { target_org: string }; Returns: boolean };
      accept_org_invitation: { Args: { target_org: string }; Returns: boolean };
      manage_org_member: { Args: { target_org: string; target_user: string; new_role: Database["public"]["Enums"]["member_role"]; new_status: string }; Returns: boolean };
      revoke_org_invitation: { Args: { target_org: string; invitation_id: string }; Returns: boolean };
      save_custom_role: { Args: { target_org: string; role_name: string; permission_doc: Json }; Returns: string };
      assign_custom_role: { Args: { target_org: string; target_user: string; target_role: string | null }; Returns: boolean };
      transfer_organization_owner: { Args: { target_org: string; new_owner: string }; Returns: boolean };
      store_org_invitation: { Args: { target_org: string; invite_email: string; invited_user: string; assigned_role: Database["public"]["Enums"]["member_role"]; actor_id: string }; Returns: string };
      create_invoice_with_item: { Args: { target_org: string; target_client: string; new_invoice_number: string; invoice_currency: string; invoice_tax: number; new_issue_date: string; new_due_date: string; line_description: string; line_quantity: number; line_unit_price: number }; Returns: string };
      create_invoice_credit: { Args: { target_org: string; target_invoice: string; new_credit_number: string; credit_amount: number; credit_reason: string; actor_id: string }; Returns: string };
      create_invoice_refund: { Args: { target_org: string; target_invoice: string; target_payment: string; refund_amount: number; refund_reason: string; actor_id: string }; Returns: string };
      register_integration: { Args: { target_org: string; provider_key: string; display_label: string }; Returns: string };
      remove_integration: { Args: { target_org: string; integration_id: string }; Returns: boolean };
      save_task_automation: { Args: { target_org: string; rule_id: string | null; rule_name: string; rule_description: string; task_title: string; task_description: string; task_priority: string; enable_rule: boolean; trigger_mode?: string; interval_minutes?: number }; Returns: string };
      set_automation_enabled: { Args: { target_org: string; rule_id: string; enable_rule: boolean }; Returns: boolean };
      run_task_automation: { Args: { target_org: string; rule_id: string; request_key: string }; Returns: string };
      retry_automation_run: { Args: { target_org: string; run_id: string; request_key: string }; Returns: string };
      store_slack_integration: { Args: { target_org: string; slack_team_id: string; slack_team_name: string; encrypted_credentials: string; token_expires_at: string | null; granted_scopes: string[] }; Returns: string };
      claim_ai_request: { Args: { target_org: string; target_user: string; request_limit?: number }; Returns: boolean };
      process_automation_jobs: { Args: { batch_size?: number }; Returns: number };
      convert_won_lead_to_client: { Args: { target_org: string; target_lead: string }; Returns: string };
      submit_content_review: { Args: { target_org: string; target_item: string; review_decision: string; review_feedback?: string }; Returns: string };
    };
    Enums: {
      member_role: "owner" | "admin" | "manager" | "member" | "client";
      record_status: "active" | "archived";
      lead_stage: "new" | "qualified" | "proposal" | "negotiation" | "won" | "lost";
      project_status: "planned" | "in_progress" | "internal_review" | "client_review" | "completed" | "on_hold";
      task_status: "todo" | "in_progress" | "blocked" | "done";
      content_status: "draft" | "review" | "approved" | "scheduled" | "published";
      invoice_status: "draft" | "sent" | "partially_paid" | "paid" | "overdue" | "void";
    };
    CompositeTypes: Record<string, never>;
  };
};

export type Tables<T extends keyof Database["public"]["Tables"]> = Database["public"]["Tables"][T]["Row"];
export type Enums<T extends keyof Database["public"]["Enums"]> = Database["public"]["Enums"][T];
