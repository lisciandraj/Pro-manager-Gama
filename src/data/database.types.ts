export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      accounting_accounts: {
        Row: {
          active: boolean
          code: string
          created_at: string
          id: string
          is_system: boolean
          localization_country: string | null
          localization_source_code: string | null
          name: string
          type: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          code: string
          created_at?: string
          id?: string
          is_system?: boolean
          localization_country?: string | null
          localization_source_code?: string | null
          name: string
          type: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          code?: string
          created_at?: string
          id?: string
          is_system?: boolean
          localization_country?: string | null
          localization_source_code?: string | null
          name?: string
          type?: string
          updated_at?: string
        }
        Relationships: []
      }
      accounting_entries: {
        Row: {
          created_at: string
          created_by: string | null
          entry_date: string
          id: string
          journal_id: string
          memo: string | null
          number: string
          posted_at: string | null
          posted_by: string | null
          reference: string | null
          request_key: string | null
          reversal_of: string | null
          source_id: string | null
          source_type: string
          status: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          entry_date: string
          id?: string
          journal_id: string
          memo?: string | null
          number?: string
          posted_at?: string | null
          posted_by?: string | null
          reference?: string | null
          request_key?: string | null
          reversal_of?: string | null
          source_id?: string | null
          source_type?: string
          status?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          entry_date?: string
          id?: string
          journal_id?: string
          memo?: string | null
          number?: string
          posted_at?: string | null
          posted_by?: string | null
          reference?: string | null
          request_key?: string | null
          reversal_of?: string | null
          source_id?: string | null
          source_type?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "accounting_entries_journal_id_fkey"
            columns: ["journal_id"]
            isOneToOne: false
            referencedRelation: "accounting_journals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "accounting_entries_reversal_of_fkey"
            columns: ["reversal_of"]
            isOneToOne: false
            referencedRelation: "accounting_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      accounting_entry_lines: {
        Row: {
          account_id: string
          credit: number
          debit: number
          entry_id: string
          id: string
          label: string | null
          partner_id: string | null
          partner_type: string | null
          position: number
          project_id: string | null
          tax_id: string | null
        }
        Insert: {
          account_id: string
          credit?: number
          debit?: number
          entry_id: string
          id?: string
          label?: string | null
          partner_id?: string | null
          partner_type?: string | null
          position?: number
          project_id?: string | null
          tax_id?: string | null
        }
        Update: {
          account_id?: string
          credit?: number
          debit?: number
          entry_id?: string
          id?: string
          label?: string | null
          partner_id?: string | null
          partner_type?: string | null
          position?: number
          project_id?: string | null
          tax_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "accounting_entry_lines_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounting_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "accounting_entry_lines_entry_id_fkey"
            columns: ["entry_id"]
            isOneToOne: false
            referencedRelation: "accounting_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "accounting_entry_lines_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "pm_projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "accounting_entry_lines_tax_id_fkey"
            columns: ["tax_id"]
            isOneToOne: false
            referencedRelation: "accounting_taxes"
            referencedColumns: ["id"]
          },
        ]
      }
      accounting_journals: {
        Row: {
          active: boolean
          code: string
          created_at: string
          financial_account_id: string | null
          id: string
          kind: string
          name: string
        }
        Insert: {
          active?: boolean
          code: string
          created_at?: string
          financial_account_id?: string | null
          id?: string
          kind: string
          name: string
        }
        Update: {
          active?: boolean
          code?: string
          created_at?: string
          financial_account_id?: string | null
          id?: string
          kind?: string
          name?: string
        }
        Relationships: [
          {
            foreignKeyName: "accounting_journals_financial_account_id_fkey"
            columns: ["financial_account_id"]
            isOneToOne: false
            referencedRelation: "financial_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      accounting_periods: {
        Row: {
          closed_at: string | null
          closed_by: string | null
          created_at: string
          id: string
          period_end: string
          period_start: string
          reopened_at: string | null
          reopened_by: string | null
          status: string
        }
        Insert: {
          closed_at?: string | null
          closed_by?: string | null
          created_at?: string
          id?: string
          period_end: string
          period_start: string
          reopened_at?: string | null
          reopened_by?: string | null
          status?: string
        }
        Update: {
          closed_at?: string | null
          closed_by?: string | null
          created_at?: string
          id?: string
          period_end?: string
          period_start?: string
          reopened_at?: string | null
          reopened_by?: string | null
          status?: string
        }
        Relationships: []
      }
      accounting_permissions: {
        Row: {
          can_close: boolean
          can_create: boolean
          can_delete: boolean
          can_edit: boolean
          can_export: boolean
          can_validate: boolean
          can_view: boolean
          profile_id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          can_close?: boolean
          can_create?: boolean
          can_delete?: boolean
          can_edit?: boolean
          can_export?: boolean
          can_validate?: boolean
          can_view?: boolean
          profile_id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          can_close?: boolean
          can_create?: boolean
          can_delete?: boolean
          can_edit?: boolean
          can_export?: boolean
          can_validate?: boolean
          can_view?: boolean
          profile_id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "accounting_permissions_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: true
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "accounting_permissions_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      accounting_taxes: {
        Row: {
          active: boolean
          code: string
          collected_account_id: string | null
          country: string | null
          created_at: string
          deductible_account_id: string | null
          id: string
          kind: string
          name: string
          rate: number
          valid_from: string | null
        }
        Insert: {
          active?: boolean
          code: string
          collected_account_id?: string | null
          country?: string | null
          created_at?: string
          deductible_account_id?: string | null
          id?: string
          kind?: string
          name: string
          rate: number
          valid_from?: string | null
        }
        Update: {
          active?: boolean
          code?: string
          collected_account_id?: string | null
          country?: string | null
          created_at?: string
          deductible_account_id?: string | null
          id?: string
          kind?: string
          name?: string
          rate?: number
          valid_from?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "accounting_taxes_collected_account_id_fkey"
            columns: ["collected_account_id"]
            isOneToOne: false
            referencedRelation: "accounting_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "accounting_taxes_deductible_account_id_fkey"
            columns: ["deductible_account_id"]
            isOneToOne: false
            referencedRelation: "accounting_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      app_modules: {
        Row: {
          enabled: boolean
          id: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          enabled?: boolean
          id: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          enabled?: boolean
          id?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      bank_transactions: {
        Row: {
          amount: number
          created_by: string | null
          description: string
          financial_account_id: string
          id: string
          import_batch: string | null
          imported_at: string
          reference: string | null
          status: string
          value_date: string
        }
        Insert: {
          amount: number
          created_by?: string | null
          description: string
          financial_account_id: string
          id?: string
          import_batch?: string | null
          imported_at?: string
          reference?: string | null
          status?: string
          value_date: string
        }
        Update: {
          amount?: number
          created_by?: string | null
          description?: string
          financial_account_id?: string
          id?: string
          import_batch?: string | null
          imported_at?: string
          reference?: string | null
          status?: string
          value_date?: string
        }
        Relationships: [
          {
            foreignKeyName: "bank_transactions_financial_account_id_fkey"
            columns: ["financial_account_id"]
            isOneToOne: false
            referencedRelation: "financial_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      commercial_matrix: {
        Row: {
          active: boolean
          created_at: string
          id: string
          margin: number | null
          margin_percent: number | null
          product_id: string
          purchase_price: number
          sale_price: number
          supplier_id: string | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          id?: string
          margin?: number | null
          margin_percent?: number | null
          product_id: string
          purchase_price?: number
          sale_price?: number
          supplier_id?: string | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          created_at?: string
          id?: string
          margin?: number | null
          margin_percent?: number | null
          product_id?: string
          purchase_price?: number
          sale_price?: number
          supplier_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "commercial_matrix_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "catalog_products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "commercial_matrix_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "commercial_matrix_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "replenishment_needs"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "commercial_matrix_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      company_settings: {
        Row: {
          address: string
          company_version: number
          configured: boolean
          country: string
          currency: string
          document_primary: string
          document_secondary: string
          email: string
          fiscal_year_start_month: number
          id: boolean
          legal_name: string
          localization_country: string | null
          localization_version: string | null
          logo_data: string
          payable_account_id: string | null
          phone: string
          purchase_account_id: string | null
          receivable_account_id: string | null
          sales_account_id: string | null
          tax_collected_account_id: string | null
          tax_deductible_account_id: string | null
          tax_id: string
          updated_at: string
          updated_by: string | null
          website: string
        }
        Insert: {
          address?: string
          company_version?: number
          configured?: boolean
          country?: string
          currency?: string
          document_primary?: string
          document_secondary?: string
          email?: string
          fiscal_year_start_month?: number
          id?: boolean
          legal_name?: string
          localization_country?: string | null
          localization_version?: string | null
          logo_data?: string
          payable_account_id?: string | null
          phone?: string
          purchase_account_id?: string | null
          receivable_account_id?: string | null
          sales_account_id?: string | null
          tax_collected_account_id?: string | null
          tax_deductible_account_id?: string | null
          tax_id?: string
          updated_at?: string
          updated_by?: string | null
          website?: string
        }
        Update: {
          address?: string
          company_version?: number
          configured?: boolean
          country?: string
          currency?: string
          document_primary?: string
          document_secondary?: string
          email?: string
          fiscal_year_start_month?: number
          id?: boolean
          legal_name?: string
          localization_country?: string | null
          localization_version?: string | null
          logo_data?: string
          payable_account_id?: string | null
          phone?: string
          purchase_account_id?: string | null
          receivable_account_id?: string | null
          sales_account_id?: string | null
          tax_collected_account_id?: string | null
          tax_deductible_account_id?: string | null
          tax_id?: string
          updated_at?: string
          updated_by?: string | null
          website?: string
        }
        Relationships: [
          {
            foreignKeyName: "company_settings_payable_account_id_fkey"
            columns: ["payable_account_id"]
            isOneToOne: false
            referencedRelation: "accounting_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_settings_purchase_account_id_fkey"
            columns: ["purchase_account_id"]
            isOneToOne: false
            referencedRelation: "accounting_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_settings_receivable_account_id_fkey"
            columns: ["receivable_account_id"]
            isOneToOne: false
            referencedRelation: "accounting_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_settings_sales_account_id_fkey"
            columns: ["sales_account_id"]
            isOneToOne: false
            referencedRelation: "accounting_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_settings_tax_collected_account_id_fkey"
            columns: ["tax_collected_account_id"]
            isOneToOne: false
            referencedRelation: "accounting_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_settings_tax_deductible_account_id_fkey"
            columns: ["tax_deductible_account_id"]
            isOneToOne: false
            referencedRelation: "accounting_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      crm_activities: {
        Row: {
          body: string | null
          contact_id: string | null
          created_at: string
          created_by: string | null
          customer_id: string | null
          customer_request_id: string | null
          done_at: string | null
          due_at: string | null
          id: string
          invoice_id: string | null
          kind: string
          lead_id: string | null
          opportunity_id: string | null
          owner_id: string | null
          priority: string
          remind_at: string | null
          status: string
          subject: string
          updated_at: string
        }
        Insert: {
          body?: string | null
          contact_id?: string | null
          created_at?: string
          created_by?: string | null
          customer_id?: string | null
          customer_request_id?: string | null
          done_at?: string | null
          due_at?: string | null
          id?: string
          invoice_id?: string | null
          kind: string
          lead_id?: string | null
          opportunity_id?: string | null
          owner_id?: string | null
          priority?: string
          remind_at?: string | null
          status?: string
          subject: string
          updated_at?: string
        }
        Update: {
          body?: string | null
          contact_id?: string | null
          created_at?: string
          created_by?: string | null
          customer_id?: string | null
          customer_request_id?: string | null
          done_at?: string | null
          due_at?: string | null
          id?: string
          invoice_id?: string | null
          kind?: string
          lead_id?: string | null
          opportunity_id?: string | null
          owner_id?: string | null
          priority?: string
          remind_at?: string | null
          status?: string
          subject?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "crm_activities_contact_id_fkey"
            columns: ["contact_id"]
            isOneToOne: false
            referencedRelation: "crm_contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_activities_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_activities_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_activities_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_activities_customer_request_id_fkey"
            columns: ["customer_request_id"]
            isOneToOne: false
            referencedRelation: "customer_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_activities_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_activities_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "crm_leads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_activities_opportunity_id_fkey"
            columns: ["opportunity_id"]
            isOneToOne: false
            referencedRelation: "crm_opportunities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_activities_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_activities_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      crm_contacts: {
        Row: {
          active: boolean
          created_at: string
          created_by: string | null
          customer_id: string | null
          decision_role: string | null
          email: string | null
          first_name: string | null
          id: string
          is_primary: boolean
          job_title: string | null
          last_name: string | null
          lead_id: string | null
          linkedin: string | null
          notes: string | null
          phone: string | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          created_by?: string | null
          customer_id?: string | null
          decision_role?: string | null
          email?: string | null
          first_name?: string | null
          id?: string
          is_primary?: boolean
          job_title?: string | null
          last_name?: string | null
          lead_id?: string | null
          linkedin?: string | null
          notes?: string | null
          phone?: string | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          created_at?: string
          created_by?: string | null
          customer_id?: string | null
          decision_role?: string | null
          email?: string | null
          first_name?: string | null
          id?: string
          is_primary?: boolean
          job_title?: string | null
          last_name?: string | null
          lead_id?: string | null
          linkedin?: string | null
          notes?: string | null
          phone?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "crm_contacts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_contacts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_contacts_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_contacts_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "crm_leads"
            referencedColumns: ["id"]
          },
        ]
      }
      crm_leads: {
        Row: {
          active: boolean
          address: string | null
          city: string | null
          company: string | null
          company_size: string | null
          converted_at: string | null
          converted_customer_id: string | null
          country: string | null
          created_at: string
          created_by: string | null
          email: string | null
          first_name: string | null
          id: string
          industry: string | null
          job_title: string | null
          kind: string
          last_interaction_at: string | null
          last_name: string | null
          next_followup_at: string | null
          notes: string | null
          owner_id: string | null
          phone: string | null
          phone2: string | null
          priority: string
          score: number
          source_id: string | null
          status: string
          updated_at: string
          website: string | null
        }
        Insert: {
          active?: boolean
          address?: string | null
          city?: string | null
          company?: string | null
          company_size?: string | null
          converted_at?: string | null
          converted_customer_id?: string | null
          country?: string | null
          created_at?: string
          created_by?: string | null
          email?: string | null
          first_name?: string | null
          id?: string
          industry?: string | null
          job_title?: string | null
          kind?: string
          last_interaction_at?: string | null
          last_name?: string | null
          next_followup_at?: string | null
          notes?: string | null
          owner_id?: string | null
          phone?: string | null
          phone2?: string | null
          priority?: string
          score?: number
          source_id?: string | null
          status?: string
          updated_at?: string
          website?: string | null
        }
        Update: {
          active?: boolean
          address?: string | null
          city?: string | null
          company?: string | null
          company_size?: string | null
          converted_at?: string | null
          converted_customer_id?: string | null
          country?: string | null
          created_at?: string
          created_by?: string | null
          email?: string | null
          first_name?: string | null
          id?: string
          industry?: string | null
          job_title?: string | null
          kind?: string
          last_interaction_at?: string | null
          last_name?: string | null
          next_followup_at?: string | null
          notes?: string | null
          owner_id?: string | null
          phone?: string | null
          phone2?: string | null
          priority?: string
          score?: number
          source_id?: string | null
          status?: string
          updated_at?: string
          website?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "crm_leads_converted_customer_id_fkey"
            columns: ["converted_customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_leads_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_leads_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_leads_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_leads_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_leads_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "crm_sources"
            referencedColumns: ["id"]
          },
        ]
      }
      crm_lost_reasons: {
        Row: {
          active: boolean
          created_at: string
          id: string
          name: string
          sort_order: number
          updated_at: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          id?: string
          name: string
          sort_order?: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          created_at?: string
          id?: string
          name?: string
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
      crm_opportunities: {
        Row: {
          active: boolean
          amount: number
          competitors: string | null
          contact_id: string | null
          created_at: string
          created_by: string | null
          customer_id: string | null
          description: string | null
          expected_close_date: string | null
          id: string
          lead_id: string | null
          lost_at: string | null
          lost_reason_id: string | null
          owner_id: string | null
          priority: string
          probability: number
          quote_invoice_id: string | null
          reference: string
          source_id: string | null
          stage_id: string
          title: string
          updated_at: string
          weighted_amount: number | null
          won_at: string | null
        }
        Insert: {
          active?: boolean
          amount?: number
          competitors?: string | null
          contact_id?: string | null
          created_at?: string
          created_by?: string | null
          customer_id?: string | null
          description?: string | null
          expected_close_date?: string | null
          id?: string
          lead_id?: string | null
          lost_at?: string | null
          lost_reason_id?: string | null
          owner_id?: string | null
          priority?: string
          probability?: number
          quote_invoice_id?: string | null
          reference?: string
          source_id?: string | null
          stage_id: string
          title: string
          updated_at?: string
          weighted_amount?: number | null
          won_at?: string | null
        }
        Update: {
          active?: boolean
          amount?: number
          competitors?: string | null
          contact_id?: string | null
          created_at?: string
          created_by?: string | null
          customer_id?: string | null
          description?: string | null
          expected_close_date?: string | null
          id?: string
          lead_id?: string | null
          lost_at?: string | null
          lost_reason_id?: string | null
          owner_id?: string | null
          priority?: string
          probability?: number
          quote_invoice_id?: string | null
          reference?: string
          source_id?: string | null
          stage_id?: string
          title?: string
          updated_at?: string
          weighted_amount?: number | null
          won_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "crm_opportunities_contact_id_fkey"
            columns: ["contact_id"]
            isOneToOne: false
            referencedRelation: "crm_contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_opportunities_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_opportunities_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_opportunities_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_opportunities_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "crm_leads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_opportunities_lost_reason_id_fkey"
            columns: ["lost_reason_id"]
            isOneToOne: false
            referencedRelation: "crm_lost_reasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_opportunities_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_opportunities_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_opportunities_quote_invoice_id_fkey"
            columns: ["quote_invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_opportunities_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "crm_sources"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_opportunities_stage_id_fkey"
            columns: ["stage_id"]
            isOneToOne: false
            referencedRelation: "crm_pipeline_stages"
            referencedColumns: ["id"]
          },
        ]
      }
      crm_opportunity_lines: {
        Row: {
          created_at: string
          discount: number
          id: string
          opportunity_id: string
          position: number
          product_id: string
          quantity: number
          unit_price: number
        }
        Insert: {
          created_at?: string
          discount?: number
          id?: string
          opportunity_id: string
          position?: number
          product_id: string
          quantity?: number
          unit_price?: number
        }
        Update: {
          created_at?: string
          discount?: number
          id?: string
          opportunity_id?: string
          position?: number
          product_id?: string
          quantity?: number
          unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: "crm_opportunity_lines_opportunity_id_fkey"
            columns: ["opportunity_id"]
            isOneToOne: false
            referencedRelation: "crm_opportunities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_opportunity_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "catalog_products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_opportunity_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_opportunity_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "replenishment_needs"
            referencedColumns: ["product_id"]
          },
        ]
      }
      crm_pipeline_stages: {
        Row: {
          active: boolean
          created_at: string
          default_probability: number
          id: string
          is_lost: boolean
          is_won: boolean
          name: string
          sort_order: number
          updated_at: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          default_probability?: number
          id?: string
          is_lost?: boolean
          is_won?: boolean
          name: string
          sort_order?: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          created_at?: string
          default_probability?: number
          id?: string
          is_lost?: boolean
          is_won?: boolean
          name?: string
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
      crm_scoring_rules: {
        Row: {
          active: boolean
          created_at: string
          event_key: string
          id: string
          label: string
          points: number
          updated_at: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          event_key: string
          id?: string
          label: string
          points: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          created_at?: string
          event_key?: string
          id?: string
          label?: string
          points?: number
          updated_at?: string
        }
        Relationships: []
      }
      crm_sources: {
        Row: {
          active: boolean
          created_at: string
          id: string
          name: string
          sort_order: number
          updated_at: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          id?: string
          name: string
          sort_order?: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          created_at?: string
          id?: string
          name?: string
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
      crm_targets: {
        Row: {
          amount_goal: number
          created_at: string
          created_by: string | null
          id: string
          notes: string | null
          period_kind: string
          period_start: string
          profile_id: string | null
          updated_at: string
        }
        Insert: {
          amount_goal: number
          created_at?: string
          created_by?: string | null
          id?: string
          notes?: string | null
          period_kind: string
          period_start: string
          profile_id?: string | null
          updated_at?: string
        }
        Update: {
          amount_goal?: number
          created_at?: string
          created_by?: string | null
          id?: string
          notes?: string | null
          period_kind?: string
          period_start?: string
          profile_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "crm_targets_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_targets_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_targets_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "crm_targets_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      customer_request_lines: {
        Row: {
          created_at: string
          id: string
          line_total: number
          product_id: string
          quantity: number
          request_id: string
          tax_rate: number
          unit_price: number
        }
        Insert: {
          created_at?: string
          id?: string
          line_total?: number
          product_id: string
          quantity: number
          request_id: string
          tax_rate?: number
          unit_price?: number
        }
        Update: {
          created_at?: string
          id?: string
          line_total?: number
          product_id?: string
          quantity?: number
          request_id?: string
          tax_rate?: number
          unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: "customer_request_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "catalog_products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_request_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_request_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "replenishment_needs"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "customer_request_lines_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "customer_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      customer_requests: {
        Row: {
          converted_at: string | null
          created_at: string
          created_by: string | null
          customer_id: string | null
          id: string
          invoice_id: string | null
          notes: string | null
          requester_email: string | null
          requester_name: string | null
          status: string
          total: number
          updated_at: string
        }
        Insert: {
          converted_at?: string | null
          created_at?: string
          created_by?: string | null
          customer_id?: string | null
          id?: string
          invoice_id?: string | null
          notes?: string | null
          requester_email?: string | null
          requester_name?: string | null
          status?: string
          total?: number
          updated_at?: string
        }
        Update: {
          converted_at?: string | null
          created_at?: string
          created_by?: string | null
          customer_id?: string | null
          id?: string
          invoice_id?: string | null
          notes?: string | null
          requester_email?: string | null
          requester_name?: string | null
          status?: string
          total?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "customer_requests_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_requests_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      customer_special_prices: {
        Row: {
          contract_ref: string | null
          created_at: string
          customer_id: string
          id: string
          product_id: string
          unit_price: number
        }
        Insert: {
          contract_ref?: string | null
          created_at?: string
          customer_id: string
          id?: string
          product_id: string
          unit_price: number
        }
        Update: {
          contract_ref?: string | null
          created_at?: string
          customer_id?: string
          id?: string
          product_id?: string
          unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: "customer_special_prices_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_special_prices_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "catalog_products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_special_prices_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_special_prices_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "replenishment_needs"
            referencedColumns: ["product_id"]
          },
        ]
      }
      customers: {
        Row: {
          active: boolean
          address: string | null
          category: string
          city: string | null
          created_at: string
          crm_score: number
          email: string | null
          id: string
          identification: string | null
          name: string
          notes: string | null
          owner_id: string | null
          payment_terms_days: number | null
          phone: string | null
          province: string | null
          source_id: string | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          address?: string | null
          category?: string
          city?: string | null
          created_at?: string
          crm_score?: number
          email?: string | null
          id?: string
          identification?: string | null
          name: string
          notes?: string | null
          owner_id?: string | null
          payment_terms_days?: number | null
          phone?: string | null
          province?: string | null
          source_id?: string | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          address?: string | null
          category?: string
          city?: string | null
          created_at?: string
          crm_score?: number
          email?: string | null
          id?: string
          identification?: string | null
          name?: string
          notes?: string | null
          owner_id?: string | null
          payment_terms_days?: number | null
          phone?: string | null
          province?: string | null
          source_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "customers_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customers_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customers_source_id_fkey"
            columns: ["source_id"]
            isOneToOne: false
            referencedRelation: "crm_sources"
            referencedColumns: ["id"]
          },
        ]
      }
      expense_categories: {
        Row: {
          account_id: string | null
          active: boolean
          id: string
          name: string
          sort_order: number
        }
        Insert: {
          account_id?: string | null
          active?: boolean
          id?: string
          name: string
          sort_order?: number
        }
        Update: {
          account_id?: string | null
          active?: boolean
          id?: string
          name?: string
          sort_order?: number
        }
        Relationships: [
          {
            foreignKeyName: "expense_categories_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounting_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      expense_receipts: {
        Row: {
          created_at: string
          created_by: string | null
          data_url: string
          expense_id: string
          filename: string
          id: string
          mime_type: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          data_url: string
          expense_id: string
          filename: string
          id?: string
          mime_type: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          data_url?: string
          expense_id?: string
          filename?: string
          id?: string
          mime_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "expense_receipts_expense_id_fkey"
            columns: ["expense_id"]
            isOneToOne: false
            referencedRelation: "expenses"
            referencedColumns: ["id"]
          },
        ]
      }
      expenses: {
        Row: {
          amount_total: number
          amount_untaxed: number
          category_id: string | null
          created_at: string
          created_by: string | null
          currency: string
          description: string
          expense_date: string
          financial_account_id: string | null
          id: string
          notes: string | null
          payment_method: string | null
          project_id: string | null
          reference: string
          request_key: string | null
          status: string
          supplier_id: string | null
          tax_amount: number
          tax_id: string | null
          updated_at: string
        }
        Insert: {
          amount_total: number
          amount_untaxed: number
          category_id?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          description: string
          expense_date: string
          financial_account_id?: string | null
          id?: string
          notes?: string | null
          payment_method?: string | null
          project_id?: string | null
          reference?: string
          request_key?: string | null
          status?: string
          supplier_id?: string | null
          tax_amount?: number
          tax_id?: string | null
          updated_at?: string
        }
        Update: {
          amount_total?: number
          amount_untaxed?: number
          category_id?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          description?: string
          expense_date?: string
          financial_account_id?: string | null
          id?: string
          notes?: string | null
          payment_method?: string | null
          project_id?: string | null
          reference?: string
          request_key?: string | null
          status?: string
          supplier_id?: string | null
          tax_amount?: number
          tax_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "expenses_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "expense_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_financial_account_id_fkey"
            columns: ["financial_account_id"]
            isOneToOne: false
            referencedRelation: "financial_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "pm_projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "expenses_tax_id_fkey"
            columns: ["tax_id"]
            isOneToOne: false
            referencedRelation: "accounting_taxes"
            referencedColumns: ["id"]
          },
        ]
      }
      external_invoice_deliveries: {
        Row: {
          created_at: string
          created_by: string
          delivery_id: string
          invoice_id: string
        }
        Insert: {
          created_at?: string
          created_by: string
          delivery_id: string
          invoice_id: string
        }
        Update: {
          created_at?: string
          created_by?: string
          delivery_id?: string
          invoice_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "external_invoice_deliveries_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "sales_deliveries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "external_invoice_deliveries_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "external_invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      external_invoice_files: {
        Row: {
          content_base64: string
          created_at: string
          filename: string
          id: string
          invoice_id: string
          mime_type: string
        }
        Insert: {
          content_base64: string
          created_at?: string
          filename: string
          id?: string
          invoice_id: string
          mime_type: string
        }
        Update: {
          content_base64?: string
          created_at?: string
          filename?: string
          id?: string
          invoice_id?: string
          mime_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "external_invoice_files_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "external_invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      external_invoice_lines: {
        Row: {
          id: string
          invoice_id: string
          order_line_id: string
          quantity: number
        }
        Insert: {
          id?: string
          invoice_id: string
          order_line_id: string
          quantity: number
        }
        Update: {
          id?: string
          invoice_id?: string
          order_line_id?: string
          quantity?: number
        }
        Relationships: [
          {
            foreignKeyName: "external_invoice_lines_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "external_invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "external_invoice_lines_order_line_id_fkey"
            columns: ["order_line_id"]
            isOneToOne: false
            referencedRelation: "sales_order_lines"
            referencedColumns: ["id"]
          },
        ]
      }
      external_invoice_payments: {
        Row: {
          account: string
          amount: number
          cancellation_reason: string | null
          cancelled_at: string | null
          cancelled_by: string | null
          created_at: string
          created_by: string
          financial_account_id: string | null
          id: string
          invoice_id: string
          method: string
          notes: string
          paid_at: string
          reference: string
          request_key: string
          status: string
        }
        Insert: {
          account?: string
          amount: number
          cancellation_reason?: string | null
          cancelled_at?: string | null
          cancelled_by?: string | null
          created_at?: string
          created_by: string
          financial_account_id?: string | null
          id?: string
          invoice_id: string
          method: string
          notes?: string
          paid_at?: string
          reference?: string
          request_key: string
          status?: string
        }
        Update: {
          account?: string
          amount?: number
          cancellation_reason?: string | null
          cancelled_at?: string | null
          cancelled_by?: string | null
          created_at?: string
          created_by?: string
          financial_account_id?: string | null
          id?: string
          invoice_id?: string
          method?: string
          notes?: string
          paid_at?: string
          reference?: string
          request_key?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "external_invoice_payments_financial_account_id_fkey"
            columns: ["financial_account_id"]
            isOneToOne: false
            referencedRelation: "financial_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "external_invoice_payments_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "external_invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      external_invoices: {
        Row: {
          access_key: string | null
          cancellation_reason: string | null
          created_at: string
          created_by: string
          document_kind: string
          document_snapshot: Json | null
          due_date: string | null
          external_issue_date: string | null
          external_number: string | null
          external_status: string | null
          fiscal_status: string
          id: string
          issue_date: string
          issuer_ruc: string | null
          notes: string
          number: string
          order_id: string
          payment_delivery_date: string | null
          payment_terms_days: number | null
          request_key: string
          software: string
          source_quote_id: string | null
          subtotal: number
          tax: number
          total: number | null
          updated_at: string
        }
        Insert: {
          access_key?: string | null
          cancellation_reason?: string | null
          created_at?: string
          created_by: string
          document_kind?: string
          document_snapshot?: Json | null
          due_date?: string | null
          external_issue_date?: string | null
          external_number?: string | null
          external_status?: string | null
          fiscal_status: string
          id?: string
          issue_date: string
          issuer_ruc?: string | null
          notes?: string
          number: string
          order_id: string
          payment_delivery_date?: string | null
          payment_terms_days?: number | null
          request_key: string
          software?: string
          source_quote_id?: string | null
          subtotal: number
          tax: number
          total?: number | null
          updated_at?: string
        }
        Update: {
          access_key?: string | null
          cancellation_reason?: string | null
          created_at?: string
          created_by?: string
          document_kind?: string
          document_snapshot?: Json | null
          due_date?: string | null
          external_issue_date?: string | null
          external_number?: string | null
          external_status?: string | null
          fiscal_status?: string
          id?: string
          issue_date?: string
          issuer_ruc?: string | null
          notes?: string
          number?: string
          order_id?: string
          payment_delivery_date?: string | null
          payment_terms_days?: number | null
          request_key?: string
          software?: string
          source_quote_id?: string | null
          subtotal?: number
          tax?: number
          total?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "external_invoices_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "sales_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "external_invoices_source_quote_id_fkey"
            columns: ["source_quote_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      favorite_order_lines: {
        Row: {
          favorite_order_id: string
          id: string
          product_id: string
          quantity: number
        }
        Insert: {
          favorite_order_id: string
          id?: string
          product_id: string
          quantity: number
        }
        Update: {
          favorite_order_id?: string
          id?: string
          product_id?: string
          quantity?: number
        }
        Relationships: [
          {
            foreignKeyName: "favorite_order_lines_favorite_order_id_fkey"
            columns: ["favorite_order_id"]
            isOneToOne: false
            referencedRelation: "favorite_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "favorite_order_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "catalog_products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "favorite_order_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "favorite_order_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "replenishment_needs"
            referencedColumns: ["product_id"]
          },
        ]
      }
      favorite_orders: {
        Row: {
          created_at: string
          created_by: string
          id: string
          name: string
        }
        Insert: {
          created_at?: string
          created_by: string
          id?: string
          name: string
        }
        Update: {
          created_at?: string
          created_by?: string
          id?: string
          name?: string
        }
        Relationships: []
      }
      financial_accounts: {
        Row: {
          account_id: string | null
          active: boolean
          bank_name: string | null
          created_at: string
          created_by: string | null
          currency: string
          id: string
          kind: string
          name: string
          opening_balance: number
          updated_at: string
        }
        Insert: {
          account_id?: string | null
          active?: boolean
          bank_name?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          id?: string
          kind: string
          name: string
          opening_balance?: number
          updated_at?: string
        }
        Update: {
          account_id?: string | null
          active?: boolean
          bank_name?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          id?: string
          kind?: string
          name?: string
          opening_balance?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "financial_accounts_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounting_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      fleet_alert_log: {
        Row: {
          alert_key: string
          detail: string | null
          driver_id: string | null
          due_on: string | null
          id: string
          kind: string
          notified_at: string
          vehicle_id: string | null
        }
        Insert: {
          alert_key: string
          detail?: string | null
          driver_id?: string | null
          due_on?: string | null
          id?: string
          kind: string
          notified_at?: string
          vehicle_id?: string | null
        }
        Update: {
          alert_key?: string
          detail?: string | null
          driver_id?: string | null
          due_on?: string | null
          id?: string
          kind?: string
          notified_at?: string
          vehicle_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fleet_alert_log_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "fleet_drivers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fleet_alert_log_vehicle_id_fkey"
            columns: ["vehicle_id"]
            isOneToOne: false
            referencedRelation: "fleet_vehicles"
            referencedColumns: ["id"]
          },
        ]
      }
      fleet_assignments: {
        Row: {
          created_at: string
          created_by: string | null
          driver_id: string
          ended_on: string | null
          id: string
          notes: string | null
          started_on: string
          vehicle_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          driver_id: string
          ended_on?: string | null
          id?: string
          notes?: string | null
          started_on: string
          vehicle_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          driver_id?: string
          ended_on?: string | null
          id?: string
          notes?: string | null
          started_on?: string
          vehicle_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "fleet_assignments_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "fleet_drivers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fleet_assignments_vehicle_id_fkey"
            columns: ["vehicle_id"]
            isOneToOne: false
            referencedRelation: "fleet_vehicles"
            referencedColumns: ["id"]
          },
        ]
      }
      fleet_documents: {
        Row: {
          created_at: string
          created_by: string | null
          data_url: string | null
          expires_on: string | null
          filename: string | null
          id: string
          issued_on: string | null
          kind: string
          mime_type: string | null
          notes: string | null
          reference: string | null
          updated_at: string
          vehicle_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          data_url?: string | null
          expires_on?: string | null
          filename?: string | null
          id?: string
          issued_on?: string | null
          kind: string
          mime_type?: string | null
          notes?: string | null
          reference?: string | null
          updated_at?: string
          vehicle_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          data_url?: string | null
          expires_on?: string | null
          filename?: string | null
          id?: string
          issued_on?: string | null
          kind?: string
          mime_type?: string | null
          notes?: string | null
          reference?: string | null
          updated_at?: string
          vehicle_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "fleet_documents_vehicle_id_fkey"
            columns: ["vehicle_id"]
            isOneToOne: false
            referencedRelation: "fleet_vehicles"
            referencedColumns: ["id"]
          },
        ]
      }
      fleet_drivers: {
        Row: {
          active: boolean
          created_at: string
          created_by: string | null
          employee_id: string | null
          id: string
          is_demo: boolean
          licence_categories: string[]
          licence_expiry: string | null
          licence_number: string | null
          name: string
          notes: string | null
          phone: string | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          created_by?: string | null
          employee_id?: string | null
          id?: string
          is_demo?: boolean
          licence_categories?: string[]
          licence_expiry?: string | null
          licence_number?: string | null
          name: string
          notes?: string | null
          phone?: string | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          created_at?: string
          created_by?: string | null
          employee_id?: string | null
          id?: string
          is_demo?: boolean
          licence_categories?: string[]
          licence_expiry?: string | null
          licence_number?: string | null
          name?: string
          notes?: string | null
          phone?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "fleet_drivers_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "hr_employees"
            referencedColumns: ["id"]
          },
        ]
      }
      fleet_fuel_logs: {
        Row: {
          amount: number
          created_at: string
          created_by: string | null
          driver_id: string | null
          full_tank: boolean
          id: string
          litres: number
          logged_on: string
          notes: string | null
          odometer: number
          request_key: string | null
          station: string | null
          vehicle_id: string
        }
        Insert: {
          amount: number
          created_at?: string
          created_by?: string | null
          driver_id?: string | null
          full_tank?: boolean
          id?: string
          litres: number
          logged_on: string
          notes?: string | null
          odometer: number
          request_key?: string | null
          station?: string | null
          vehicle_id: string
        }
        Update: {
          amount?: number
          created_at?: string
          created_by?: string | null
          driver_id?: string | null
          full_tank?: boolean
          id?: string
          litres?: number
          logged_on?: string
          notes?: string | null
          odometer?: number
          request_key?: string | null
          station?: string | null
          vehicle_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "fleet_fuel_logs_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "fleet_drivers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fleet_fuel_logs_vehicle_id_fkey"
            columns: ["vehicle_id"]
            isOneToOne: false
            referencedRelation: "fleet_vehicles"
            referencedColumns: ["id"]
          },
        ]
      }
      fleet_maintenance: {
        Row: {
          cost: number
          created_at: string
          created_by: string | null
          garage: string | null
          id: string
          kind: string
          next_service_odometer: number | null
          next_service_on: string | null
          notes: string | null
          odometer: number | null
          performed_on: string
          request_key: string | null
          vehicle_id: string
        }
        Insert: {
          cost?: number
          created_at?: string
          created_by?: string | null
          garage?: string | null
          id?: string
          kind: string
          next_service_odometer?: number | null
          next_service_on?: string | null
          notes?: string | null
          odometer?: number | null
          performed_on: string
          request_key?: string | null
          vehicle_id: string
        }
        Update: {
          cost?: number
          created_at?: string
          created_by?: string | null
          garage?: string | null
          id?: string
          kind?: string
          next_service_odometer?: number | null
          next_service_on?: string | null
          notes?: string | null
          odometer?: number | null
          performed_on?: string
          request_key?: string | null
          vehicle_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "fleet_maintenance_vehicle_id_fkey"
            columns: ["vehicle_id"]
            isOneToOne: false
            referencedRelation: "fleet_vehicles"
            referencedColumns: ["id"]
          },
        ]
      }
      fleet_vehicles: {
        Row: {
          active: boolean
          brand: string
          cargo_volume_m3: number | null
          created_at: string
          created_by: string | null
          energy: string
          first_registration: string | null
          gvwr_kg: number | null
          id: string
          is_demo: boolean
          kind: string
          model: string
          notes: string | null
          odometer: number
          payload_kg: number | null
          photo: string | null
          plate: string
          reference: string
          status: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          brand: string
          cargo_volume_m3?: number | null
          created_at?: string
          created_by?: string | null
          energy: string
          first_registration?: string | null
          gvwr_kg?: number | null
          id?: string
          is_demo?: boolean
          kind: string
          model: string
          notes?: string | null
          odometer?: number
          payload_kg?: number | null
          photo?: string | null
          plate: string
          reference?: string
          status?: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          brand?: string
          cargo_volume_m3?: number | null
          created_at?: string
          created_by?: string | null
          energy?: string
          first_registration?: string | null
          gvwr_kg?: number | null
          id?: string
          is_demo?: boolean
          kind?: string
          model?: string
          notes?: string | null
          odometer?: number
          payload_kg?: number | null
          photo?: string | null
          plate?: string
          reference?: string
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      fulfillment_incidents: {
        Row: {
          created_at: string
          created_by: string
          id: string
          kind: string
          pick_line_id: string
          preparation_id: string
          quantity: number
          reason: string
        }
        Insert: {
          created_at?: string
          created_by: string
          id?: string
          kind: string
          pick_line_id: string
          preparation_id: string
          quantity: number
          reason: string
        }
        Update: {
          created_at?: string
          created_by?: string
          id?: string
          kind?: string
          pick_line_id?: string
          preparation_id?: string
          quantity?: number
          reason?: string
        }
        Relationships: [
          {
            foreignKeyName: "fulfillment_incidents_pick_line_id_fkey"
            columns: ["pick_line_id"]
            isOneToOne: false
            referencedRelation: "fulfillment_pick_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fulfillment_incidents_preparation_id_fkey"
            columns: ["preparation_id"]
            isOneToOne: false
            referencedRelation: "fulfillment_preparations"
            referencedColumns: ["id"]
          },
        ]
      }
      fulfillment_package_lines: {
        Row: {
          package_id: string
          pick_line_id: string
          quantity: number
        }
        Insert: {
          package_id: string
          pick_line_id: string
          quantity: number
        }
        Update: {
          package_id?: string
          pick_line_id?: string
          quantity?: number
        }
        Relationships: [
          {
            foreignKeyName: "fulfillment_package_lines_package_id_fkey"
            columns: ["package_id"]
            isOneToOne: false
            referencedRelation: "fulfillment_packages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fulfillment_package_lines_pick_line_id_fkey"
            columns: ["pick_line_id"]
            isOneToOne: false
            referencedRelation: "fulfillment_pick_lines"
            referencedColumns: ["id"]
          },
        ]
      }
      fulfillment_packages: {
        Row: {
          barcode: string
          created_at: string
          created_by: string
          height_cm: number | null
          id: string
          length_cm: number | null
          preparation_id: string
          status: string
          weight_kg: number | null
          width_cm: number | null
        }
        Insert: {
          barcode?: string
          created_at?: string
          created_by: string
          height_cm?: number | null
          id?: string
          length_cm?: number | null
          preparation_id: string
          status?: string
          weight_kg?: number | null
          width_cm?: number | null
        }
        Update: {
          barcode?: string
          created_at?: string
          created_by?: string
          height_cm?: number | null
          id?: string
          length_cm?: number | null
          preparation_id?: string
          status?: string
          weight_kg?: number | null
          width_cm?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "fulfillment_packages_preparation_id_fkey"
            columns: ["preparation_id"]
            isOneToOne: false
            referencedRelation: "fulfillment_preparations"
            referencedColumns: ["id"]
          },
        ]
      }
      fulfillment_pick_lines: {
        Row: {
          id: string
          order_line_id: string
          picked: number
          planned: number
          preparation_id: string
          source_location_id: string
          stage_location_id: string | null
        }
        Insert: {
          id?: string
          order_line_id: string
          picked?: number
          planned: number
          preparation_id: string
          source_location_id: string
          stage_location_id?: string | null
        }
        Update: {
          id?: string
          order_line_id?: string
          picked?: number
          planned?: number
          preparation_id?: string
          source_location_id?: string
          stage_location_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fulfillment_pick_lines_order_line_id_fkey"
            columns: ["order_line_id"]
            isOneToOne: false
            referencedRelation: "sales_order_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fulfillment_pick_lines_preparation_id_fkey"
            columns: ["preparation_id"]
            isOneToOne: false
            referencedRelation: "fulfillment_preparations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fulfillment_pick_lines_source_location_id_fkey"
            columns: ["source_location_id"]
            isOneToOne: false
            referencedRelation: "warehouse_locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fulfillment_pick_lines_stage_location_id_fkey"
            columns: ["stage_location_id"]
            isOneToOne: false
            referencedRelation: "warehouse_locations"
            referencedColumns: ["id"]
          },
        ]
      }
      fulfillment_preparations: {
        Row: {
          assigned_to: string | null
          created_at: string
          id: string
          number: string
          order_id: string
          partial_reason: string | null
          shipment_id: string | null
          status: string
          updated_at: string
        }
        Insert: {
          assigned_to?: string | null
          created_at?: string
          id?: string
          number?: string
          order_id: string
          partial_reason?: string | null
          shipment_id?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          assigned_to?: string | null
          created_at?: string
          id?: string
          number?: string
          order_id?: string
          partial_reason?: string | null
          shipment_id?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "fulfillment_preparations_assigned_to_fkey"
            columns: ["assigned_to"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fulfillment_preparations_assigned_to_fkey"
            columns: ["assigned_to"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fulfillment_preparations_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "sales_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fulfillment_preparations_shipment_id_fkey"
            columns: ["shipment_id"]
            isOneToOne: true
            referencedRelation: "sales_deliveries"
            referencedColumns: ["id"]
          },
        ]
      }
      gama_ai_history: {
        Row: {
          answer: Json | null
          completed_at: string | null
          created_at: string
          engine: string | null
          id: string
          language: string
          question: string
          status: string
          user_id: string
        }
        Insert: {
          answer?: Json | null
          completed_at?: string | null
          created_at?: string
          engine?: string | null
          id: string
          language: string
          question: string
          status?: string
          user_id: string
        }
        Update: {
          answer?: Json | null
          completed_at?: string | null
          created_at?: string
          engine?: string | null
          id?: string
          language?: string
          question?: string
          status?: string
          user_id?: string
        }
        Relationships: []
      }
      gama_ai_settings: {
        Row: {
          encrypted_key: string
          id: boolean
          model: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          encrypted_key: string
          id?: boolean
          model?: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          encrypted_key?: string
          id?: boolean
          model?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      gama_audit: {
        Row: {
          action: string
          actor_id: string | null
          actor_role: string | null
          changed_at: string
          changed_fields: string[] | null
          id: number
          new_data: Json | null
          old_data: Json | null
          row_id: string
          table_name: string
        }
        Insert: {
          action: string
          actor_id?: string | null
          actor_role?: string | null
          changed_at?: string
          changed_fields?: string[] | null
          id?: number
          new_data?: Json | null
          old_data?: Json | null
          row_id: string
          table_name: string
        }
        Update: {
          action?: string
          actor_id?: string | null
          actor_role?: string | null
          changed_at?: string
          changed_fields?: string[] | null
          id?: number
          new_data?: Json | null
          old_data?: Json | null
          row_id?: string
          table_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "gama_audit_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gama_audit_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      gama_document_references: {
        Row: {
          document_id: string
          document_reference: string
          dossier_number: number
          node_index: number
          ordinal: number
          table_name: string
        }
        Insert: {
          document_id: string
          document_reference?: string
          dossier_number: number
          node_index?: never
          ordinal?: number
          table_name: string
        }
        Update: {
          document_id?: string
          document_reference?: string
          dossier_number?: number
          node_index?: never
          ordinal?: number
          table_name?: string
        }
        Relationships: []
      }
      hr_absence_decisions: {
        Row: {
          absence_id: string
          created_at: string
          employee_id: string
          id: string
          reason: string
          reviewed_by: string
          status: string
        }
        Insert: {
          absence_id: string
          created_at?: string
          employee_id: string
          id?: string
          reason: string
          reviewed_by: string
          status: string
        }
        Update: {
          absence_id?: string
          created_at?: string
          employee_id?: string
          id?: string
          reason?: string
          reviewed_by?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "hr_absence_decisions_absence_id_fkey"
            columns: ["absence_id"]
            isOneToOne: false
            referencedRelation: "hr_absences"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_absence_decisions_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "hr_employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_absence_decisions_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_absence_decisions_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_absence_private: {
        Row: {
          absence_id: string
          reason: string | null
        }
        Insert: {
          absence_id: string
          reason?: string | null
        }
        Update: {
          absence_id?: string
          reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "hr_absence_private_absence_id_fkey"
            columns: ["absence_id"]
            isOneToOne: true
            referencedRelation: "hr_absences"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_absences: {
        Row: {
          created_at: string
          days: number | null
          decision_reason: string | null
          employee_id: string
          end_date: string
          end_fraction: number
          id: string
          kind: string
          reviewed_at: string | null
          reviewed_by: string | null
          start_date: string
          start_fraction: number
          status: string
        }
        Insert: {
          created_at?: string
          days?: number | null
          decision_reason?: string | null
          employee_id: string
          end_date: string
          end_fraction?: number
          id?: string
          kind?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          start_date: string
          start_fraction?: number
          status?: string
        }
        Update: {
          created_at?: string
          days?: number | null
          decision_reason?: string | null
          employee_id?: string
          end_date?: string
          end_fraction?: number
          id?: string
          kind?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          start_date?: string
          start_fraction?: number
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "hr_absences_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "hr_employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_absences_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_absences_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_attendance: {
        Row: {
          break_seconds: number
          break_started_at: string | null
          correction_reason: string | null
          employee_id: string
          ended_at: string | null
          id: string
          reviewed_at: string | null
          reviewed_by: string | null
          started_at: string
          status: string
        }
        Insert: {
          break_seconds?: number
          break_started_at?: string | null
          correction_reason?: string | null
          employee_id: string
          ended_at?: string | null
          id?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          started_at?: string
          status?: string
        }
        Update: {
          break_seconds?: number
          break_started_at?: string | null
          correction_reason?: string | null
          employee_id?: string
          ended_at?: string | null
          id?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          started_at?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "hr_attendance_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "hr_employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_attendance_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_attendance_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_audit: {
        Row: {
          action: string
          actor_id: string | null
          after_data: Json | null
          before_data: Json | null
          changed_at: string
          employee_id: string | null
          id: number
          record_id: string
          table_name: string
        }
        Insert: {
          action: string
          actor_id?: string | null
          after_data?: Json | null
          before_data?: Json | null
          changed_at?: string
          employee_id?: string | null
          id?: never
          record_id: string
          table_name: string
        }
        Update: {
          action?: string
          actor_id?: string | null
          after_data?: Json | null
          before_data?: Json | null
          changed_at?: string
          employee_id?: string | null
          id?: never
          record_id?: string
          table_name?: string
        }
        Relationships: []
      }
      hr_documents: {
        Row: {
          created_at: string
          created_by: string
          effective_date: string
          employee_id: string
          expires_on: string | null
          filename: string
          id: string
          kind: string
          storage_path: string
          supersedes_id: string | null
          title: string
        }
        Insert: {
          created_at?: string
          created_by?: string
          effective_date: string
          employee_id: string
          expires_on?: string | null
          filename: string
          id?: string
          kind: string
          storage_path: string
          supersedes_id?: string | null
          title: string
        }
        Update: {
          created_at?: string
          created_by?: string
          effective_date?: string
          employee_id?: string
          expires_on?: string | null
          filename?: string
          id?: string
          kind?: string
          storage_path?: string
          supersedes_id?: string | null
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "hr_documents_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_documents_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_documents_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "hr_employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_documents_supersedes_id_fkey"
            columns: ["supersedes_id"]
            isOneToOne: false
            referencedRelation: "hr_documents"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_employee_private: {
        Row: {
          annual_leave_days: number
          contract_type: string | null
          email: string | null
          employee_id: string
          end_date: string | null
          hire_date: string | null
          identification: string | null
          notes: string | null
          phone: string | null
          salary: number | null
        }
        Insert: {
          annual_leave_days?: number
          contract_type?: string | null
          email?: string | null
          employee_id: string
          end_date?: string | null
          hire_date?: string | null
          identification?: string | null
          notes?: string | null
          phone?: string | null
          salary?: number | null
        }
        Update: {
          annual_leave_days?: number
          contract_type?: string | null
          email?: string | null
          employee_id?: string
          end_date?: string | null
          hire_date?: string | null
          identification?: string | null
          notes?: string | null
          phone?: string | null
          salary?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "hr_employee_private_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: true
            referencedRelation: "hr_employees"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_employees: {
        Row: {
          active: boolean
          created_at: string
          department: string | null
          full_name: string
          id: string
          manager_profile_id: string | null
          position: string | null
          profile_id: string | null
        }
        Insert: {
          active?: boolean
          created_at?: string
          department?: string | null
          full_name: string
          id?: string
          manager_profile_id?: string | null
          position?: string | null
          profile_id?: string | null
        }
        Update: {
          active?: boolean
          created_at?: string
          department?: string | null
          full_name?: string
          id?: string
          manager_profile_id?: string | null
          position?: string | null
          profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "hr_employees_manager_profile_id_fkey"
            columns: ["manager_profile_id"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_employees_manager_profile_id_fkey"
            columns: ["manager_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_employees_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_employees_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_holidays: {
        Row: {
          day: string
          label: string
        }
        Insert: {
          day: string
          label: string
        }
        Update: {
          day?: string
          label?: string
        }
        Relationships: []
      }
      hr_leave_accounts: {
        Row: {
          accrual_mode: string
          active_from: string | null
          active_to: string | null
          adjustment: number
          carryover: number
          employee_id: string
          entitlement: number
          id: string
          reason: string
          year: number
        }
        Insert: {
          accrual_mode?: string
          active_from?: string | null
          active_to?: string | null
          adjustment?: number
          carryover?: number
          employee_id: string
          entitlement: number
          id?: string
          reason: string
          year: number
        }
        Update: {
          accrual_mode?: string
          active_from?: string | null
          active_to?: string | null
          adjustment?: number
          carryover?: number
          employee_id?: string
          entitlement?: number
          id?: string
          reason?: string
          year?: number
        }
        Relationships: [
          {
            foreignKeyName: "hr_leave_accounts_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "hr_employees"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_payroll: {
        Row: {
          cost_center: string
          created_at: string
          employee_id: string
          employer_cost: number
          gross: number
          id: string
          net: number
          period: string
          source_ref: string
          status: string
        }
        Insert: {
          cost_center?: string
          created_at?: string
          employee_id: string
          employer_cost: number
          gross: number
          id?: string
          net: number
          period: string
          source_ref: string
          status?: string
        }
        Update: {
          cost_center?: string
          created_at?: string
          employee_id?: string
          employer_cost?: number
          gross?: number
          id?: string
          net?: number
          period?: string
          source_ref?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "hr_payroll_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "hr_employees"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_payroll_payments: {
        Row: {
          amount: number
          created_at: string
          id: string
          paid_on: string
          payroll_id: string
          reason: string | null
          reference: string
          status: string
        }
        Insert: {
          amount: number
          created_at?: string
          id?: string
          paid_on: string
          payroll_id: string
          reason?: string | null
          reference: string
          status?: string
        }
        Update: {
          amount?: number
          created_at?: string
          id?: string
          paid_on?: string
          payroll_id?: string
          reason?: string | null
          reference?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "hr_payroll_payments_payroll_id_fkey"
            columns: ["payroll_id"]
            isOneToOne: false
            referencedRelation: "hr_payroll"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_permissions: {
        Row: {
          profile_id: string
          role: string
        }
        Insert: {
          profile_id: string
          role: string
        }
        Update: {
          profile_id?: string
          role?: string
        }
        Relationships: [
          {
            foreignKeyName: "hr_permissions_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: true
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "hr_permissions_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_shifts: {
        Row: {
          break_minutes: number
          employee_id: string
          ends_at: string
          id: string
          note: string | null
          starts_at: string
        }
        Insert: {
          break_minutes?: number
          employee_id: string
          ends_at: string
          id?: string
          note?: string | null
          starts_at: string
        }
        Update: {
          break_minutes?: number
          employee_id?: string
          ends_at?: string
          id?: string
          note?: string | null
          starts_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "hr_shifts_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "hr_employees"
            referencedColumns: ["id"]
          },
        ]
      }
      hr_work_patterns: {
        Row: {
          daily_hours: number
          effective_from: string
          employee_id: string
          id: string
          weekdays: number[]
        }
        Insert: {
          daily_hours?: number
          effective_from: string
          employee_id: string
          id?: string
          weekdays?: number[]
        }
        Update: {
          daily_hours?: number
          effective_from?: string
          employee_id?: string
          id?: string
          weekdays?: number[]
        }
        Relationships: [
          {
            foreignKeyName: "hr_work_patterns_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "hr_employees"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_count_lines: {
        Row: {
          count_id: string
          counted_quantity: number | null
          expected_quantity: number
          id: string
          location_id: string
          product_id: string
          validated: boolean
          variance: number | null
        }
        Insert: {
          count_id: string
          counted_quantity?: number | null
          expected_quantity?: number
          id?: string
          location_id: string
          product_id: string
          validated?: boolean
          variance?: number | null
        }
        Update: {
          count_id?: string
          counted_quantity?: number | null
          expected_quantity?: number
          id?: string
          location_id?: string
          product_id?: string
          validated?: boolean
          variance?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "inventory_count_lines_count_id_fkey"
            columns: ["count_id"]
            isOneToOne: false
            referencedRelation: "inventory_counts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_count_lines_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "warehouse_locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_count_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "catalog_products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_count_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_count_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "replenishment_needs"
            referencedColumns: ["product_id"]
          },
        ]
      }
      inventory_counts: {
        Row: {
          completed_at: string | null
          created_at: string
          created_by: string | null
          id: string
          reference: string
          started_at: string | null
          status: string
          warehouse_id: string
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          reference: string
          started_at?: string | null
          status?: string
          warehouse_id: string
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          reference?: string
          started_at?: string | null
          status?: string
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_counts_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      invoice_lines: {
        Row: {
          id: string
          invoice_id: string
          line_total: number
          product_id: string
          quantity: number
          quote_description: string | null
          quote_discount: number
          quote_list_price: number | null
          tax_rate: number
          unit_price: number
        }
        Insert: {
          id?: string
          invoice_id: string
          line_total?: number
          product_id: string
          quantity: number
          quote_description?: string | null
          quote_discount?: number
          quote_list_price?: number | null
          tax_rate?: number
          unit_price: number
        }
        Update: {
          id?: string
          invoice_id?: string
          line_total?: number
          product_id?: string
          quantity?: number
          quote_description?: string | null
          quote_discount?: number
          quote_list_price?: number | null
          tax_rate?: number
          unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: "invoice_lines_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "catalog_products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "replenishment_needs"
            referencedColumns: ["product_id"]
          },
        ]
      }
      invoices: {
        Row: {
          archive_number: number | null
          created_at: string
          customer_id: string | null
          id: string
          invoice_number: string | null
          issue_date: string
          notes: string | null
          quote_acceptance_channel: string | null
          quote_acceptance_reference: string | null
          quote_accepted_at: string | null
          quote_accepted_by: string | null
          quote_details: Json
          quote_request_key: string | null
          quote_revision: number
          quote_sent_at: string | null
          quote_state: string | null
          quote_valid_until: string | null
          status: string
          subtotal: number
          tax: number
          total: number
          updated_at: string
          user_id: string | null
        }
        Insert: {
          archive_number?: number | null
          created_at?: string
          customer_id?: string | null
          id?: string
          invoice_number?: string | null
          issue_date?: string
          notes?: string | null
          quote_acceptance_channel?: string | null
          quote_acceptance_reference?: string | null
          quote_accepted_at?: string | null
          quote_accepted_by?: string | null
          quote_details?: Json
          quote_request_key?: string | null
          quote_revision?: number
          quote_sent_at?: string | null
          quote_state?: string | null
          quote_valid_until?: string | null
          status?: string
          subtotal?: number
          tax?: number
          total?: number
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          archive_number?: number | null
          created_at?: string
          customer_id?: string | null
          id?: string
          invoice_number?: string | null
          issue_date?: string
          notes?: string | null
          quote_acceptance_channel?: string | null
          quote_acceptance_reference?: string | null
          quote_accepted_at?: string | null
          quote_accepted_by?: string | null
          quote_details?: Json
          quote_request_key?: string | null
          quote_revision?: number
          quote_sent_at?: string | null
          quote_state?: string | null
          quote_valid_until?: string | null
          status?: string
          subtotal?: number
          tax?: number
          total?: number
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "invoices_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
        ]
      }
      knowledge_articles: {
        Row: {
          body: string
          created_at: string
          created_by: string | null
          id: string
          parent_id: string | null
          properties: Json
          slug: string | null
          title: string
          updated_at: string
          updated_by: string | null
          version: number
        }
        Insert: {
          body: string
          created_at?: string
          created_by?: string | null
          id?: string
          parent_id?: string | null
          properties?: Json
          slug?: string | null
          title: string
          updated_at?: string
          updated_by?: string | null
          version?: number
        }
        Update: {
          body?: string
          created_at?: string
          created_by?: string | null
          id?: string
          parent_id?: string | null
          properties?: Json
          slug?: string | null
          title?: string
          updated_at?: string
          updated_by?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "knowledge_articles_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "knowledge_articles"
            referencedColumns: ["id"]
          },
        ]
      }
      pm_comments: {
        Row: {
          body: string
          created_at: string
          created_by: string
          id: string
          item_id: string | null
          project_id: string
        }
        Insert: {
          body: string
          created_at?: string
          created_by: string
          id?: string
          item_id?: string | null
          project_id: string
        }
        Update: {
          body?: string
          created_at?: string
          created_by?: string
          id?: string
          item_id?: string | null
          project_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pm_comments_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_comments_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_comments_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "pm_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_comments_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "pm_projects"
            referencedColumns: ["id"]
          },
        ]
      }
      pm_files: {
        Row: {
          created_at: string
          created_by: string
          filename: string
          id: string
          item_id: string | null
          project_id: string
          storage_path: string | null
          supersedes_id: string | null
          url: string | null
          version: number
        }
        Insert: {
          created_at?: string
          created_by: string
          filename: string
          id?: string
          item_id?: string | null
          project_id: string
          storage_path?: string | null
          supersedes_id?: string | null
          url?: string | null
          version?: number
        }
        Update: {
          created_at?: string
          created_by?: string
          filename?: string
          id?: string
          item_id?: string | null
          project_id?: string
          storage_path?: string | null
          supersedes_id?: string | null
          url?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "pm_files_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_files_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_files_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "pm_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_files_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "pm_projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_files_supersedes_id_fkey"
            columns: ["supersedes_id"]
            isOneToOne: false
            referencedRelation: "pm_files"
            referencedColumns: ["id"]
          },
        ]
      }
      pm_items: {
        Row: {
          approver_id: string | null
          created_at: string
          created_by: string
          data: Json
          deliverable_id: string | null
          description: string
          due_date: string | null
          forecast_date: string | null
          id: string
          kind: string
          owner_id: string | null
          phase_id: string | null
          priority: string
          progress: number
          project_id: string
          reference: string
          start_date: string | null
          status: string
          title: string
          updated_at: string
          version: number
          work_package_id: string | null
        }
        Insert: {
          approver_id?: string | null
          created_at?: string
          created_by: string
          data?: Json
          deliverable_id?: string | null
          description?: string
          due_date?: string | null
          forecast_date?: string | null
          id?: string
          kind: string
          owner_id?: string | null
          phase_id?: string | null
          priority?: string
          progress?: number
          project_id: string
          reference: string
          start_date?: string | null
          status: string
          title: string
          updated_at?: string
          version?: number
          work_package_id?: string | null
        }
        Update: {
          approver_id?: string | null
          created_at?: string
          created_by?: string
          data?: Json
          deliverable_id?: string | null
          description?: string
          due_date?: string | null
          forecast_date?: string | null
          id?: string
          kind?: string
          owner_id?: string | null
          phase_id?: string | null
          priority?: string
          progress?: number
          project_id?: string
          reference?: string
          start_date?: string | null
          status?: string
          title?: string
          updated_at?: string
          version?: number
          work_package_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "pm_items_approver_id_fkey"
            columns: ["approver_id"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_items_approver_id_fkey"
            columns: ["approver_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_items_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_items_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_items_deliverable_id_fkey"
            columns: ["deliverable_id"]
            isOneToOne: false
            referencedRelation: "pm_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_items_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_items_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_items_phase_id_fkey"
            columns: ["phase_id"]
            isOneToOne: false
            referencedRelation: "pm_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_items_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "pm_projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_items_work_package_id_fkey"
            columns: ["work_package_id"]
            isOneToOne: false
            referencedRelation: "pm_items"
            referencedColumns: ["id"]
          },
        ]
      }
      pm_links: {
        Row: {
          created_at: string
          created_by: string
          currency: string | null
          exchange_rate: number
          id: string
          item_id: string | null
          kind: string
          project_id: string
          target_id: string
        }
        Insert: {
          created_at?: string
          created_by: string
          currency?: string | null
          exchange_rate?: number
          id?: string
          item_id?: string | null
          kind: string
          project_id: string
          target_id: string
        }
        Update: {
          created_at?: string
          created_by?: string
          currency?: string | null
          exchange_rate?: number
          id?: string
          item_id?: string | null
          kind?: string
          project_id?: string
          target_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pm_links_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_links_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_links_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "pm_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_links_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "pm_projects"
            referencedColumns: ["id"]
          },
        ]
      }
      pm_members: {
        Row: {
          capacity_hours: number
          id: string
          profile_id: string
          project_id: string
          role: string
        }
        Insert: {
          capacity_hours?: number
          id?: string
          profile_id: string
          project_id: string
          role?: string
        }
        Update: {
          capacity_hours?: number
          id?: string
          profile_id?: string
          project_id?: string
          role?: string
        }
        Relationships: [
          {
            foreignKeyName: "pm_members_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_members_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_members_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "pm_projects"
            referencedColumns: ["id"]
          },
        ]
      }
      pm_projects: {
        Row: {
          budget: number
          budget_tolerance: number
          business_case: string
          closed_at: string | null
          closure: Json
          created_at: string
          created_by: string
          currency: string
          customer_id: string | null
          department: string
          description: string
          due_date: string
          estimate_remaining: number | null
          forecast_date: string | null
          id: string
          manager_id: string
          mode: string
          name: string
          priority: string
          project_type: string
          reference: string
          schedule_tolerance: number
          scope: string
          sponsor_id: string | null
          start_date: string
          status: string
          updated_at: string
          version: number
        }
        Insert: {
          budget?: number
          budget_tolerance?: number
          business_case?: string
          closed_at?: string | null
          closure?: Json
          created_at?: string
          created_by: string
          currency?: string
          customer_id?: string | null
          department?: string
          description?: string
          due_date: string
          estimate_remaining?: number | null
          forecast_date?: string | null
          id?: string
          manager_id: string
          mode?: string
          name: string
          priority?: string
          project_type?: string
          reference?: string
          schedule_tolerance?: number
          scope?: string
          sponsor_id?: string | null
          start_date: string
          status?: string
          updated_at?: string
          version?: number
        }
        Update: {
          budget?: number
          budget_tolerance?: number
          business_case?: string
          closed_at?: string | null
          closure?: Json
          created_at?: string
          created_by?: string
          currency?: string
          customer_id?: string | null
          department?: string
          description?: string
          due_date?: string
          estimate_remaining?: number | null
          forecast_date?: string | null
          id?: string
          manager_id?: string
          mode?: string
          name?: string
          priority?: string
          project_type?: string
          reference?: string
          schedule_tolerance?: number
          scope?: string
          sponsor_id?: string | null
          start_date?: string
          status?: string
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "pm_projects_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_projects_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_projects_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_projects_manager_id_fkey"
            columns: ["manager_id"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_projects_manager_id_fkey"
            columns: ["manager_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_projects_sponsor_id_fkey"
            columns: ["sponsor_id"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_projects_sponsor_id_fkey"
            columns: ["sponsor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      pm_templates: {
        Row: {
          code: string | null
          created_at: string
          created_by: string | null
          definition: Json
          id: string
          name: string
          updated_at: string
          version: number
        }
        Insert: {
          code?: string | null
          created_at?: string
          created_by?: string | null
          definition: Json
          id?: string
          name: string
          updated_at?: string
          version?: number
        }
        Update: {
          code?: string | null
          created_at?: string
          created_by?: string | null
          definition?: Json
          id?: string
          name?: string
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "pm_templates_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pm_templates_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      products: {
        Row: {
          active: boolean
          barcode: string | null
          brand: string | null
          category: string | null
          created_at: string
          description: string | null
          family: string | null
          has_photo: boolean | null
          id: string
          lines: string | null
          location: string | null
          max_stock: number | null
          min_stock: number
          name: string
          photo_data: string | null
          presentation: string | null
          purchase_price: number
          qty_per_carton: number | null
          reference: string | null
          sale_price: number
          sale_price_b: number
          stock: number
          supplier_id: string | null
          tax_rate: number
          updated_at: string
          volume_cm3: number | null
          weight_g: number | null
        }
        Insert: {
          active?: boolean
          barcode?: string | null
          brand?: string | null
          category?: string | null
          created_at?: string
          description?: string | null
          family?: string | null
          has_photo?: boolean | null
          id?: string
          lines?: string | null
          location?: string | null
          max_stock?: number | null
          min_stock?: number
          name: string
          photo_data?: string | null
          presentation?: string | null
          purchase_price?: number
          qty_per_carton?: number | null
          reference?: string | null
          sale_price?: number
          sale_price_b?: number
          stock?: number
          supplier_id?: string | null
          tax_rate?: number
          updated_at?: string
          volume_cm3?: number | null
          weight_g?: number | null
        }
        Update: {
          active?: boolean
          barcode?: string | null
          brand?: string | null
          category?: string | null
          created_at?: string
          description?: string | null
          family?: string | null
          has_photo?: boolean | null
          id?: string
          lines?: string | null
          location?: string | null
          max_stock?: number | null
          min_stock?: number
          name?: string
          photo_data?: string | null
          presentation?: string | null
          purchase_price?: number
          qty_per_carton?: number | null
          reference?: string | null
          sale_price?: number
          sale_price_b?: number
          stock?: number
          supplier_id?: string | null
          tax_rate?: number
          updated_at?: string
          volume_cm3?: number | null
          weight_g?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "products_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          active: boolean
          created_at: string
          email: string | null
          full_name: string
          id: string
          role: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          email?: string | null
          full_name?: string
          id: string
          role?: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          created_at?: string
          email?: string | null
          full_name?: string
          id?: string
          role?: string
          updated_at?: string
        }
        Relationships: []
      }
      purchase_order_lines: {
        Row: {
          created_at: string
          id: string
          line_total: number
          product_id: string
          purchase_order_id: string
          quantity: number
          received_quantity: number
          tax_rate: number
          unit_cost: number
        }
        Insert: {
          created_at?: string
          id?: string
          line_total?: number
          product_id: string
          purchase_order_id: string
          quantity: number
          received_quantity?: number
          tax_rate?: number
          unit_cost?: number
        }
        Update: {
          created_at?: string
          id?: string
          line_total?: number
          product_id?: string
          purchase_order_id?: string
          quantity?: number
          received_quantity?: number
          tax_rate?: number
          unit_cost?: number
        }
        Relationships: [
          {
            foreignKeyName: "purchase_order_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "catalog_products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "replenishment_needs"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "purchase_order_lines_purchase_order_id_fkey"
            columns: ["purchase_order_id"]
            isOneToOne: false
            referencedRelation: "purchase_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      purchase_orders: {
        Row: {
          created_at: string
          created_by: string | null
          expected_date: string | null
          id: string
          notes: string | null
          order_date: string
          order_number: string
          status: string
          subtotal: number
          supplier_id: string
          tax: number
          total: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          expected_date?: string | null
          id?: string
          notes?: string | null
          order_date?: string
          order_number: string
          status?: string
          subtotal?: number
          supplier_id: string
          tax?: number
          total?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          expected_date?: string | null
          id?: string
          notes?: string | null
          order_date?: string
          order_number?: string
          status?: string
          subtotal?: number
          supplier_id?: string
          tax?: number
          total?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "purchase_orders_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      quote_events: {
        Row: {
          action: string
          actor_id: string
          at: string
          detail: Json
          id: string
          quote_id: string
          revision: number
        }
        Insert: {
          action: string
          actor_id: string
          at?: string
          detail?: Json
          id?: string
          quote_id: string
          revision: number
        }
        Update: {
          action?: string
          actor_id?: string
          at?: string
          detail?: Json
          id?: string
          quote_id?: string
          revision?: number
        }
        Relationships: [
          {
            foreignKeyName: "quote_events_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      reconciliations: {
        Row: {
          amount: number
          bank_transaction_id: string
          id: string
          match_id: string | null
          match_type: string
          matched_at: string
          matched_by: string | null
          notes: string | null
        }
        Insert: {
          amount: number
          bank_transaction_id: string
          id?: string
          match_id?: string | null
          match_type: string
          matched_at?: string
          matched_by?: string | null
          notes?: string | null
        }
        Update: {
          amount?: number
          bank_transaction_id?: string
          id?: string
          match_id?: string | null
          match_type?: string
          matched_at?: string
          matched_by?: string | null
          notes?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "reconciliations_bank_transaction_id_fkey"
            columns: ["bank_transaction_id"]
            isOneToOne: true
            referencedRelation: "bank_transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      reorder_rules: {
        Row: {
          active: boolean
          created_at: string
          id: string
          lead_time_days: number | null
          max_quantity: number
          min_quantity: number
          product_id: string
          reorder_quantity: number | null
          supplier_id: string | null
          warehouse_id: string | null
        }
        Insert: {
          active?: boolean
          created_at?: string
          id?: string
          lead_time_days?: number | null
          max_quantity?: number
          min_quantity?: number
          product_id: string
          reorder_quantity?: number | null
          supplier_id?: string | null
          warehouse_id?: string | null
        }
        Update: {
          active?: boolean
          created_at?: string
          id?: string
          lead_time_days?: number | null
          max_quantity?: number
          min_quantity?: number
          product_id?: string
          reorder_quantity?: number | null
          supplier_id?: string | null
          warehouse_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "reorder_rules_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "catalog_products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reorder_rules_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reorder_rules_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "replenishment_needs"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "reorder_rules_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reorder_rules_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      return_credits: {
        Row: {
          amount: number
          created_at: string
          created_by: string | null
          data_url: string | null
          filename: string | null
          id: string
          invoice_id: string | null
          issued_on: string
          mime_type: string | null
          notes: string | null
          number: string
          return_id: string
          supplier_invoice_id: string | null
          supplier_reference: string | null
        }
        Insert: {
          amount: number
          created_at?: string
          created_by?: string | null
          data_url?: string | null
          filename?: string | null
          id?: string
          invoice_id?: string | null
          issued_on?: string
          mime_type?: string | null
          notes?: string | null
          number?: string
          return_id: string
          supplier_invoice_id?: string | null
          supplier_reference?: string | null
        }
        Update: {
          amount?: number
          created_at?: string
          created_by?: string | null
          data_url?: string | null
          filename?: string | null
          id?: string
          invoice_id?: string | null
          issued_on?: string
          mime_type?: string | null
          notes?: string | null
          number?: string
          return_id?: string
          supplier_invoice_id?: string | null
          supplier_reference?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "return_credits_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "external_invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "return_credits_return_id_fkey"
            columns: ["return_id"]
            isOneToOne: false
            referencedRelation: "return_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "return_credits_supplier_invoice_id_fkey"
            columns: ["supplier_invoice_id"]
            isOneToOne: false
            referencedRelation: "supplier_invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      return_files: {
        Row: {
          created_at: string
          created_by: string | null
          data_url: string
          filename: string
          id: string
          mime_type: string | null
          return_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          data_url: string
          filename: string
          id?: string
          mime_type?: string | null
          return_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          data_url?: string
          filename?: string
          id?: string
          mime_type?: string | null
          return_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "return_files_return_id_fkey"
            columns: ["return_id"]
            isOneToOne: false
            referencedRelation: "return_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      return_lines: {
        Row: {
          created_at: string
          delivery_line_id: string | null
          disposition: string | null
          hold_reservation_id: string | null
          id: string
          notes: string | null
          processed_at: string | null
          product_id: string
          purchase_order_line_id: string | null
          quantity: number
          quarantine_location_id: string | null
          return_id: string
          tax_rate: number
          unit_price: number
        }
        Insert: {
          created_at?: string
          delivery_line_id?: string | null
          disposition?: string | null
          hold_reservation_id?: string | null
          id?: string
          notes?: string | null
          processed_at?: string | null
          product_id: string
          purchase_order_line_id?: string | null
          quantity: number
          quarantine_location_id?: string | null
          return_id: string
          tax_rate?: number
          unit_price?: number
        }
        Update: {
          created_at?: string
          delivery_line_id?: string | null
          disposition?: string | null
          hold_reservation_id?: string | null
          id?: string
          notes?: string | null
          processed_at?: string | null
          product_id?: string
          purchase_order_line_id?: string | null
          quantity?: number
          quarantine_location_id?: string | null
          return_id?: string
          tax_rate?: number
          unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: "return_lines_delivery_line_id_fkey"
            columns: ["delivery_line_id"]
            isOneToOne: false
            referencedRelation: "sales_delivery_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "return_lines_hold_reservation_id_fkey"
            columns: ["hold_reservation_id"]
            isOneToOne: false
            referencedRelation: "stock_reservations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "return_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "catalog_products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "return_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "return_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "replenishment_needs"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "return_lines_purchase_order_line_id_fkey"
            columns: ["purchase_order_line_id"]
            isOneToOne: false
            referencedRelation: "purchase_order_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "return_lines_quarantine_location_id_fkey"
            columns: ["quarantine_location_id"]
            isOneToOne: false
            referencedRelation: "warehouse_locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "return_lines_return_id_fkey"
            columns: ["return_id"]
            isOneToOne: false
            referencedRelation: "return_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      return_orders: {
        Row: {
          carrier: string | null
          closed_at: string | null
          created_at: string
          created_by: string | null
          customer_id: string | null
          delivery_id: string | null
          financial_action: string
          id: string
          invoice_id: string | null
          kind: string
          notes: string | null
          number: string
          order_id: string | null
          processed_at: string | null
          purchase_order_id: string | null
          reason: string
          received_at: string | null
          shipped_on: string | null
          status: string
          supplier_id: string | null
          supplier_invoice_id: string | null
          tracking: string | null
          updated_at: string
        }
        Insert: {
          carrier?: string | null
          closed_at?: string | null
          created_at?: string
          created_by?: string | null
          customer_id?: string | null
          delivery_id?: string | null
          financial_action?: string
          id?: string
          invoice_id?: string | null
          kind: string
          notes?: string | null
          number?: string
          order_id?: string | null
          processed_at?: string | null
          purchase_order_id?: string | null
          reason: string
          received_at?: string | null
          shipped_on?: string | null
          status?: string
          supplier_id?: string | null
          supplier_invoice_id?: string | null
          tracking?: string | null
          updated_at?: string
        }
        Update: {
          carrier?: string | null
          closed_at?: string | null
          created_at?: string
          created_by?: string | null
          customer_id?: string | null
          delivery_id?: string | null
          financial_action?: string
          id?: string
          invoice_id?: string | null
          kind?: string
          notes?: string | null
          number?: string
          order_id?: string | null
          processed_at?: string | null
          purchase_order_id?: string | null
          reason?: string
          received_at?: string | null
          shipped_on?: string | null
          status?: string
          supplier_id?: string | null
          supplier_invoice_id?: string | null
          tracking?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "return_orders_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "return_orders_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "sales_deliveries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "return_orders_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "external_invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "return_orders_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "sales_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "return_orders_purchase_order_id_fkey"
            columns: ["purchase_order_id"]
            isOneToOne: false
            referencedRelation: "purchase_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "return_orders_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "return_orders_supplier_invoice_id_fkey"
            columns: ["supplier_invoice_id"]
            isOneToOne: false
            referencedRelation: "supplier_invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      return_refunds: {
        Row: {
          amount: number
          created_at: string
          created_by: string | null
          id: string
          method: string
          notes: string | null
          paid_at: string
          reference: string | null
          request_key: string | null
          return_id: string
        }
        Insert: {
          amount: number
          created_at?: string
          created_by?: string | null
          id?: string
          method: string
          notes?: string | null
          paid_at?: string
          reference?: string | null
          request_key?: string | null
          return_id: string
        }
        Update: {
          amount?: number
          created_at?: string
          created_by?: string | null
          id?: string
          method?: string
          notes?: string | null
          paid_at?: string
          reference?: string | null
          request_key?: string | null
          return_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "return_refunds_return_id_fkey"
            columns: ["return_id"]
            isOneToOne: false
            referencedRelation: "return_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_deliveries: {
        Row: {
          created_by: string
          departed_at: string | null
          departed_by: string | null
          departure_driver_id: string | null
          departure_vehicle: string | null
          dispatched_at: string
          id: string
          loading_required: boolean
          loading_version: number
          notes: string
          number: string
          order_id: string
          request_key: string
          tms_delivery_id: string
        }
        Insert: {
          created_by: string
          departed_at?: string | null
          departed_by?: string | null
          departure_driver_id?: string | null
          departure_vehicle?: string | null
          dispatched_at?: string
          id?: string
          loading_required?: boolean
          loading_version?: number
          notes?: string
          number?: string
          order_id: string
          request_key: string
          tms_delivery_id: string
        }
        Update: {
          created_by?: string
          departed_at?: string | null
          departed_by?: string | null
          departure_driver_id?: string | null
          departure_vehicle?: string | null
          dispatched_at?: string
          id?: string
          loading_required?: boolean
          loading_version?: number
          notes?: string
          number?: string
          order_id?: string
          request_key?: string
          tms_delivery_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sales_deliveries_departure_driver_id_fkey"
            columns: ["departure_driver_id"]
            isOneToOne: false
            referencedRelation: "fleet_drivers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_deliveries_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "sales_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_deliveries_tms_delivery_id_fkey"
            columns: ["tms_delivery_id"]
            isOneToOne: true
            referencedRelation: "tms_deliveries"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_delivery_lines: {
        Row: {
          delivery_id: string
          id: string
          loading_barcode: string | null
          location_id: string
          order_line_id: string
          quantity: number
        }
        Insert: {
          delivery_id: string
          id?: string
          loading_barcode?: string | null
          location_id: string
          order_line_id: string
          quantity: number
        }
        Update: {
          delivery_id?: string
          id?: string
          loading_barcode?: string | null
          location_id?: string
          order_line_id?: string
          quantity?: number
        }
        Relationships: [
          {
            foreignKeyName: "sales_delivery_lines_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "sales_deliveries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_delivery_lines_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "warehouse_locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_delivery_lines_order_line_id_fkey"
            columns: ["order_line_id"]
            isOneToOne: false
            referencedRelation: "sales_order_lines"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_events: {
        Row: {
          action: string
          actor_id: string
          created_at: string
          detail: Json
          entity_id: string | null
          id: string
          order_id: string
        }
        Insert: {
          action: string
          actor_id: string
          created_at?: string
          detail?: Json
          entity_id?: string | null
          id?: string
          order_id: string
        }
        Update: {
          action?: string
          actor_id?: string
          created_at?: string
          detail?: Json
          entity_id?: string | null
          id?: string
          order_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sales_events_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "sales_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_fulfillment_options: {
        Row: {
          agreement_reference: string | null
          created_at: string
          created_by: string
          id: string
          kind: string
          line_id: string
          notes: string
          order_id: string
          promised_date: string | null
          quantity: number
          replacement_product_id: string | null
          responded_at: string | null
          responded_by: string | null
          status: string
          tax_rate: number | null
          unit_price: number | null
        }
        Insert: {
          agreement_reference?: string | null
          created_at?: string
          created_by: string
          id?: string
          kind: string
          line_id: string
          notes?: string
          order_id: string
          promised_date?: string | null
          quantity: number
          replacement_product_id?: string | null
          responded_at?: string | null
          responded_by?: string | null
          status?: string
          tax_rate?: number | null
          unit_price?: number | null
        }
        Update: {
          agreement_reference?: string | null
          created_at?: string
          created_by?: string
          id?: string
          kind?: string
          line_id?: string
          notes?: string
          order_id?: string
          promised_date?: string | null
          quantity?: number
          replacement_product_id?: string | null
          responded_at?: string | null
          responded_by?: string | null
          status?: string
          tax_rate?: number | null
          unit_price?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "sales_fulfillment_options_line_id_fkey"
            columns: ["line_id"]
            isOneToOne: false
            referencedRelation: "sales_order_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_fulfillment_options_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "sales_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_fulfillment_options_replacement_product_id_fkey"
            columns: ["replacement_product_id"]
            isOneToOne: false
            referencedRelation: "catalog_products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_fulfillment_options_replacement_product_id_fkey"
            columns: ["replacement_product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_fulfillment_options_replacement_product_id_fkey"
            columns: ["replacement_product_id"]
            isOneToOne: false
            referencedRelation: "replenishment_needs"
            referencedColumns: ["product_id"]
          },
        ]
      }
      sales_order_lines: {
        Row: {
          delivery_policy: string
          id: string
          next_dispatch_quantity: number | null
          order_id: string
          product_id: string
          product_name: string
          promised_date: string | null
          quantity: number
          reference: string
          tax_rate: number
          unit_price: number
        }
        Insert: {
          delivery_policy?: string
          id?: string
          next_dispatch_quantity?: number | null
          order_id: string
          product_id: string
          product_name: string
          promised_date?: string | null
          quantity: number
          reference?: string
          tax_rate: number
          unit_price: number
        }
        Update: {
          delivery_policy?: string
          id?: string
          next_dispatch_quantity?: number | null
          order_id?: string
          product_id?: string
          product_name?: string
          promised_date?: string | null
          quantity?: number
          reference?: string
          tax_rate?: number
          unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: "sales_order_lines_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "sales_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_order_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "catalog_products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_order_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_order_lines_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "replenishment_needs"
            referencedColumns: ["product_id"]
          },
        ]
      }
      sales_orders: {
        Row: {
          created_at: string
          created_by: string
          customer_id: string
          customer_identification: string
          customer_name: string
          delivery_address: string
          id: string
          notes: string
          number: string
          request_key: string
          source_opportunity_id: string | null
          source_quote_id: string | null
          source_request_id: string | null
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by: string
          customer_id: string
          customer_identification?: string
          customer_name: string
          delivery_address?: string
          id?: string
          notes?: string
          number?: string
          request_key: string
          source_opportunity_id?: string | null
          source_quote_id?: string | null
          source_request_id?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          customer_id?: string
          customer_identification?: string
          customer_name?: string
          delivery_address?: string
          id?: string
          notes?: string
          number?: string
          request_key?: string
          source_opportunity_id?: string | null
          source_quote_id?: string | null
          source_request_id?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "sales_orders_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_orders_source_opportunity_id_fkey"
            columns: ["source_opportunity_id"]
            isOneToOne: false
            referencedRelation: "crm_opportunities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_orders_source_quote_id_fkey"
            columns: ["source_quote_id"]
            isOneToOne: true
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_orders_source_request_id_fkey"
            columns: ["source_request_id"]
            isOneToOne: true
            referencedRelation: "customer_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      sales_reservation_links: {
        Row: {
          line_id: string
          reservation_id: string
        }
        Insert: {
          line_id: string
          reservation_id: string
        }
        Update: {
          line_id?: string
          reservation_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sales_reservation_links_line_id_fkey"
            columns: ["line_id"]
            isOneToOne: false
            referencedRelation: "sales_order_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_reservation_links_reservation_id_fkey"
            columns: ["reservation_id"]
            isOneToOne: true
            referencedRelation: "stock_reservations"
            referencedColumns: ["id"]
          },
        ]
      }
      sri_electronic_documents: {
        Row: {
          ambiente: string
          authorized_xml: string | null
          clave_acceso: string | null
          cod_doc: string
          created_at: string
          fecha_autorizacion: string | null
          id: string
          invoice_id: string | null
          messages: Json
          numero_autorizacion: string | null
          secuencial: string | null
          signed_xml: string | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          ambiente: string
          authorized_xml?: string | null
          clave_acceso?: string | null
          cod_doc?: string
          created_at?: string
          fecha_autorizacion?: string | null
          id?: string
          invoice_id?: string | null
          messages?: Json
          numero_autorizacion?: string | null
          secuencial?: string | null
          signed_xml?: string | null
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          ambiente?: string
          authorized_xml?: string | null
          clave_acceso?: string | null
          cod_doc?: string
          created_at?: string
          fecha_autorizacion?: string | null
          id?: string
          invoice_id?: string | null
          messages?: Json
          numero_autorizacion?: string | null
          secuencial?: string | null
          signed_xml?: string | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sri_electronic_documents_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      sri_settings: {
        Row: {
          created_at: string
          dir_matriz: string
          email: string | null
          environment: string
          estab: string
          id: string
          pto_emi: string
          razon_social: string
          ruc: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          dir_matriz?: string
          email?: string | null
          environment?: string
          estab?: string
          id?: string
          pto_emi?: string
          razon_social: string
          ruc: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          dir_matriz?: string
          email?: string | null
          environment?: string
          estab?: string
          id?: string
          pto_emi?: string
          razon_social?: string
          ruc?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      stock_movements: {
        Row: {
          comment: string | null
          created_at: string
          destination_location_id: string | null
          id: string
          movement_type: string | null
          product_id: string
          quantity: number
          reason: string | null
          reference_id: string | null
          reference_type: string | null
          source_location_id: string | null
          stock_after: number | null
          stock_before: number | null
          type: string
          user_id: string | null
        }
        Insert: {
          comment?: string | null
          created_at?: string
          destination_location_id?: string | null
          id?: string
          movement_type?: string | null
          product_id: string
          quantity: number
          reason?: string | null
          reference_id?: string | null
          reference_type?: string | null
          source_location_id?: string | null
          stock_after?: number | null
          stock_before?: number | null
          type: string
          user_id?: string | null
        }
        Update: {
          comment?: string | null
          created_at?: string
          destination_location_id?: string | null
          id?: string
          movement_type?: string | null
          product_id?: string
          quantity?: number
          reason?: string | null
          reference_id?: string | null
          reference_type?: string | null
          source_location_id?: string | null
          stock_after?: number | null
          stock_before?: number | null
          type?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "stock_movements_destination_location_id_fkey"
            columns: ["destination_location_id"]
            isOneToOne: false
            referencedRelation: "warehouse_locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_movements_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "catalog_products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_movements_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_movements_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "replenishment_needs"
            referencedColumns: ["product_id"]
          },
          {
            foreignKeyName: "stock_movements_source_location_id_fkey"
            columns: ["source_location_id"]
            isOneToOne: false
            referencedRelation: "warehouse_locations"
            referencedColumns: ["id"]
          },
        ]
      }
      stock_quants: {
        Row: {
          id: string
          location_id: string
          product_id: string
          quantity: number
          reserved_quantity: number
          updated_at: string
        }
        Insert: {
          id?: string
          location_id: string
          product_id: string
          quantity?: number
          reserved_quantity?: number
          updated_at?: string
        }
        Update: {
          id?: string
          location_id?: string
          product_id?: string
          quantity?: number
          reserved_quantity?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "stock_quants_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "warehouse_locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_quants_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "catalog_products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_quants_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_quants_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "replenishment_needs"
            referencedColumns: ["product_id"]
          },
        ]
      }
      stock_reservations: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          location_id: string
          product_id: string
          quantity: number
          reference_id: string | null
          reference_type: string | null
          released_at: string | null
          status: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          location_id: string
          product_id: string
          quantity: number
          reference_id?: string | null
          reference_type?: string | null
          released_at?: string | null
          status?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          location_id?: string
          product_id?: string
          quantity?: number
          reference_id?: string | null
          reference_type?: string | null
          released_at?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "stock_reservations_location_id_fkey"
            columns: ["location_id"]
            isOneToOne: false
            referencedRelation: "warehouse_locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_reservations_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "catalog_products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_reservations_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_reservations_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "replenishment_needs"
            referencedColumns: ["product_id"]
          },
        ]
      }
      supplier_invoice_payments: {
        Row: {
          amount: number
          cancellation_reason: string | null
          created_at: string
          created_by: string | null
          financial_account_id: string | null
          id: string
          method: string | null
          notes: string | null
          paid_at: string
          reference: string | null
          request_key: string | null
          status: string
          supplier_invoice_id: string
        }
        Insert: {
          amount: number
          cancellation_reason?: string | null
          created_at?: string
          created_by?: string | null
          financial_account_id?: string | null
          id?: string
          method?: string | null
          notes?: string | null
          paid_at: string
          reference?: string | null
          request_key?: string | null
          status?: string
          supplier_invoice_id: string
        }
        Update: {
          amount?: number
          cancellation_reason?: string | null
          created_at?: string
          created_by?: string | null
          financial_account_id?: string | null
          id?: string
          method?: string | null
          notes?: string | null
          paid_at?: string
          reference?: string | null
          request_key?: string | null
          status?: string
          supplier_invoice_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "supplier_invoice_payments_financial_account_id_fkey"
            columns: ["financial_account_id"]
            isOneToOne: false
            referencedRelation: "financial_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_invoice_payments_supplier_invoice_id_fkey"
            columns: ["supplier_invoice_id"]
            isOneToOne: false
            referencedRelation: "supplier_invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      supplier_invoices: {
        Row: {
          created_at: string
          created_by: string | null
          due_date: string | null
          id: string
          issue_date: string
          notes: string | null
          number: string
          payment_terms_days: number | null
          project_id: string | null
          purchase_order_id: string | null
          request_key: string | null
          status: string
          subtotal: number
          supplier_id: string
          tax: number
          tax_id: string | null
          total: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          due_date?: string | null
          id?: string
          issue_date: string
          notes?: string | null
          number: string
          payment_terms_days?: number | null
          project_id?: string | null
          purchase_order_id?: string | null
          request_key?: string | null
          status?: string
          subtotal?: number
          supplier_id: string
          tax?: number
          tax_id?: string | null
          total: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          due_date?: string | null
          id?: string
          issue_date?: string
          notes?: string | null
          number?: string
          payment_terms_days?: number | null
          project_id?: string | null
          purchase_order_id?: string | null
          request_key?: string | null
          status?: string
          subtotal?: number
          supplier_id?: string
          tax?: number
          tax_id?: string | null
          total?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "supplier_invoices_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "pm_projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_invoices_purchase_order_id_fkey"
            columns: ["purchase_order_id"]
            isOneToOne: false
            referencedRelation: "purchase_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_invoices_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "supplier_invoices_tax_id_fkey"
            columns: ["tax_id"]
            isOneToOne: false
            referencedRelation: "accounting_taxes"
            referencedColumns: ["id"]
          },
        ]
      }
      suppliers: {
        Row: {
          active: boolean
          address: string | null
          city: string | null
          contact_name: string | null
          country: string | null
          created_at: string
          email: string | null
          id: string
          name: string
          notes: string | null
          phone: string | null
          postal_code: string | null
          province: string | null
          tax_id: string | null
          updated_at: string
        }
        Insert: {
          active?: boolean
          address?: string | null
          city?: string | null
          contact_name?: string | null
          country?: string | null
          created_at?: string
          email?: string | null
          id?: string
          name: string
          notes?: string | null
          phone?: string | null
          postal_code?: string | null
          province?: string | null
          tax_id?: string | null
          updated_at?: string
        }
        Update: {
          active?: boolean
          address?: string | null
          city?: string | null
          contact_name?: string | null
          country?: string | null
          created_at?: string
          email?: string | null
          id?: string
          name?: string
          notes?: string | null
          phone?: string | null
          postal_code?: string | null
          province?: string | null
          tax_id?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      tms_deliveries: {
        Row: {
          actual_arrival: string | null
          address: string
          created_at: string
          created_by: string | null
          customer: string
          customer_id: string | null
          delivered_at: string | null
          delivery_date: string
          driver_id: string | null
          id: string
          lat: number | null
          lng: number | null
          notes: string | null
          priority: string
          route_id: string | null
          status: string
          time_window: string | null
          volume: number
          weight: number
        }
        Insert: {
          actual_arrival?: string | null
          address: string
          created_at?: string
          created_by?: string | null
          customer: string
          customer_id?: string | null
          delivered_at?: string | null
          delivery_date?: string
          driver_id?: string | null
          id?: string
          lat?: number | null
          lng?: number | null
          notes?: string | null
          priority?: string
          route_id?: string | null
          status?: string
          time_window?: string | null
          volume?: number
          weight?: number
        }
        Update: {
          actual_arrival?: string | null
          address?: string
          created_at?: string
          created_by?: string | null
          customer?: string
          customer_id?: string | null
          delivered_at?: string | null
          delivery_date?: string
          driver_id?: string | null
          id?: string
          lat?: number | null
          lng?: number | null
          notes?: string | null
          priority?: string
          route_id?: string | null
          status?: string
          time_window?: string | null
          volume?: number
          weight?: number
        }
        Relationships: [
          {
            foreignKeyName: "tms_deliveries_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tms_deliveries_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tms_deliveries_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tms_deliveries_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "fleet_drivers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tms_deliveries_route_id_fkey"
            columns: ["route_id"]
            isOneToOne: false
            referencedRelation: "tms_routes"
            referencedColumns: ["id"]
          },
        ]
      }
      tms_events: {
        Row: {
          at: string
          customer: string | null
          delivery_id: string | null
          id: string
          note: string | null
          type: string
          user_id: string | null
        }
        Insert: {
          at?: string
          customer?: string | null
          delivery_id?: string | null
          id?: string
          note?: string | null
          type: string
          user_id?: string | null
        }
        Update: {
          at?: string
          customer?: string | null
          delivery_id?: string | null
          id?: string
          note?: string | null
          type?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tms_events_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "tms_deliveries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tms_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tms_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      tms_loading_allocations: {
        Row: {
          delivery_line_id: string
          quantity: number
          scan_id: string
        }
        Insert: {
          delivery_line_id: string
          quantity: number
          scan_id: string
        }
        Update: {
          delivery_line_id?: string
          quantity?: number
          scan_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tms_loading_allocations_delivery_line_id_fkey"
            columns: ["delivery_line_id"]
            isOneToOne: false
            referencedRelation: "sales_delivery_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tms_loading_allocations_scan_id_fkey"
            columns: ["scan_id"]
            isOneToOne: false
            referencedRelation: "tms_loading_scans"
            referencedColumns: ["id"]
          },
        ]
      }
      tms_loading_scans: {
        Row: {
          barcode: string
          delivery_id: string
          id: string
          quantity: number
          request_key: string
          scanned_at: string
          scanned_by: string
          void_reason: string | null
          voided_at: string | null
          voided_by: string | null
        }
        Insert: {
          barcode: string
          delivery_id: string
          id?: string
          quantity: number
          request_key: string
          scanned_at?: string
          scanned_by: string
          void_reason?: string | null
          voided_at?: string | null
          voided_by?: string | null
        }
        Update: {
          barcode?: string
          delivery_id?: string
          id?: string
          quantity?: number
          request_key?: string
          scanned_at?: string
          scanned_by?: string
          void_reason?: string | null
          voided_at?: string | null
          voided_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tms_loading_scans_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "sales_deliveries"
            referencedColumns: ["id"]
          },
        ]
      }
      tms_proofs: {
        Row: {
          captured_at: string
          captured_by: string | null
          delivery_id: string
          photo: string | null
          signature: string | null
        }
        Insert: {
          captured_at?: string
          captured_by?: string | null
          delivery_id: string
          photo?: string | null
          signature?: string | null
        }
        Update: {
          captured_at?: string
          captured_by?: string | null
          delivery_id?: string
          photo?: string | null
          signature?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tms_proofs_captured_by_fkey"
            columns: ["captured_by"]
            isOneToOne: false
            referencedRelation: "crm_team"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tms_proofs_captured_by_fkey"
            columns: ["captured_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tms_proofs_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: true
            referencedRelation: "tms_deliveries"
            referencedColumns: ["id"]
          },
        ]
      }
      tms_routes: {
        Row: {
          created_at: string
          distance: number
          driver_id: string | null
          driver_name: string | null
          id: string
          route_date: string
          status: string
          stops: Json
          vehicle: string | null
          vehicle_id: string | null
          volume: number
          weight: number
        }
        Insert: {
          created_at?: string
          distance?: number
          driver_id?: string | null
          driver_name?: string | null
          id?: string
          route_date?: string
          status?: string
          stops?: Json
          vehicle?: string | null
          vehicle_id?: string | null
          volume?: number
          weight?: number
        }
        Update: {
          created_at?: string
          distance?: number
          driver_id?: string | null
          driver_name?: string | null
          id?: string
          route_date?: string
          status?: string
          stops?: Json
          vehicle?: string | null
          vehicle_id?: string | null
          volume?: number
          weight?: number
        }
        Relationships: [
          {
            foreignKeyName: "tms_routes_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "fleet_drivers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tms_routes_vehicle_id_fkey"
            columns: ["vehicle_id"]
            isOneToOne: false
            referencedRelation: "fleet_vehicles"
            referencedColumns: ["id"]
          },
        ]
      }
      tms_settings: {
        Row: {
          depot: string | null
          depot_lat: number | null
          depot_lng: number | null
          id: boolean
          return_depot: boolean
          updated_at: string
        }
        Insert: {
          depot?: string | null
          depot_lat?: number | null
          depot_lng?: number | null
          id?: boolean
          return_depot?: boolean
          updated_at?: string
        }
        Update: {
          depot?: string | null
          depot_lat?: number | null
          depot_lng?: number | null
          id?: boolean
          return_depot?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      user_home_preferences: {
        Row: {
          kpi_selected: string[] | null
          module_order: string[]
          updated_at: string
          user_id: string
        }
        Insert: {
          kpi_selected?: string[] | null
          module_order?: string[]
          updated_at?: string
          user_id: string
        }
        Update: {
          kpi_selected?: string[] | null
          module_order?: string[]
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      warehouse_locations: {
        Row: {
          active: boolean
          barcode: string | null
          code: string
          created_at: string
          id: string
          name: string
          parent_id: string | null
          picking_priority: number
          type: string
          warehouse_id: string
        }
        Insert: {
          active?: boolean
          barcode?: string | null
          code: string
          created_at?: string
          id?: string
          name: string
          parent_id?: string | null
          picking_priority?: number
          type?: string
          warehouse_id: string
        }
        Update: {
          active?: boolean
          barcode?: string | null
          code?: string
          created_at?: string
          id?: string
          name?: string
          parent_id?: string | null
          picking_priority?: number
          type?: string
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "warehouse_locations_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "warehouse_locations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "warehouse_locations_warehouse_id_fkey"
            columns: ["warehouse_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id"]
          },
        ]
      }
      warehouses: {
        Row: {
          active: boolean
          address: string | null
          city: string | null
          code: string
          created_at: string
          id: string
          name: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          address?: string | null
          city?: string | null
          code: string
          created_at?: string
          id?: string
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          address?: string | null
          city?: string | null
          code?: string
          created_at?: string
          id?: string
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      catalog_products: {
        Row: {
          active: boolean | null
          barcode: string | null
          base_price: number | null
          category: string | null
          contract_price: boolean | null
          created_at: string | null
          has_photo: boolean | null
          id: string | null
          name: string | null
          photo_data: string | null
          reference: string | null
          sale_price: number | null
          stock: number | null
          tax_rate: number | null
        }
        Relationships: []
      }
      crm_team: {
        Row: {
          email: string | null
          full_name: string | null
          id: string | null
          role: string | null
        }
        Insert: {
          email?: string | null
          full_name?: string | null
          id?: string | null
          role?: string | null
        }
        Update: {
          email?: string | null
          full_name?: string | null
          id?: string | null
          role?: string | null
        }
        Relationships: []
      }
      replenishment_needs: {
        Row: {
          available: number | null
          incoming: number | null
          max_stock: number | null
          min_stock: number | null
          name: string | null
          on_hand: number | null
          product_id: string | null
          projected_available: number | null
          reference: string | null
          reserved: number | null
          sales_demand: number | null
          suggested_purchase: number | null
          supplier_id: string | null
          unreserved_demand: number | null
        }
        Relationships: [
          {
            foreignKeyName: "products_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      gama_accounting_action: {
        Args: { p_action: string; p_data?: Json }
        Returns: Json
      }
      gama_ai_catalog: { Args: never; Returns: Json }
      gama_ai_claim: {
        Args: {
          p_id: string
          p_language: string
          p_question: string
          p_user: string
        }
        Returns: boolean
      }
      gama_ai_overview: {
        Args: { p_from?: string; p_to?: string }
        Returns: Json
      }
      gama_ai_query: { Args: { p_query: Json }; Returns: Json }
      gama_client_deliveries: {
        Args: { p_id?: string; p_offset?: number }
        Returns: Json
      }
      gama_commercial_action: {
        Args: { p_action: string; p_data: Json }
        Returns: Json
      }
      gama_company_action: {
        Args: { p_action: string; p_data?: Json }
        Returns: Json
      }
      gama_count_generate_lines: {
        Args: { p_count_id: string }
        Returns: number
      }
      gama_count_validate: { Args: { p_count_id: string }; Returns: Json }
      gama_fleet_action: {
        Args: { p_action: string; p_data?: Json }
        Returns: Json
      }
      gama_fulfillment_action: {
        Args: { p_action: string; p_data: Json }
        Returns: Json
      }
      gama_home_kpis: {
        Args: { p_selected?: string[]; p_user?: string }
        Returns: Json
      }
      gama_home_order: {
        Args: { p_order?: string[]; p_user?: string }
        Returns: Json
      }
      gama_hr_clock: { Args: { p_action: string }; Returns: Json }
      gama_hr_directory: { Args: never; Returns: Json }
      gama_hr_licences: {
        Args: { p_action: string; p_data?: Json }
        Returns: Json
      }
      gama_hr_save_employee: {
        Args: { p_employee: Json; p_id?: string; p_private: Json }
        Returns: string
      }
      gama_internal_invoice_action: {
        Args: { p_action: string; p_data?: Json }
        Returns: Json
      }
      gama_legacy_quote_save: { Args: { p_data: Json }; Returns: Json }
      gama_loading_action: {
        Args: { p_action: string; p_data: Json }
        Returns: Json
      }
      gama_operations_action: {
        Args: { p_action: string; p_data?: Json }
        Returns: Json
      }
      gama_payment_action: {
        Args: { p_action: string; p_data?: Json }
        Returns: Json
      }
      gama_projects_action: {
        Args: { p_action: string; p_data?: Json }
        Returns: Json
      }
      gama_quote_action: {
        Args: { p_action: string; p_data: Json }
        Returns: Json
      }
      gama_quote_from_request: {
        Args: { p_data: Json; p_request_id: string }
        Returns: Json
      }
      gama_quote_reservations: { Args: { p_id: string }; Returns: Json }
      gama_receive_purchase: {
        Args: { p_comment?: string; p_lines: Json; p_purchase_order_id: string }
        Returns: Json
      }
      gama_register_stock_movement: {
        Args: {
          p_comment?: string
          p_product_id: string
          p_quantity: number
          p_reason?: string
          p_type: string
        }
        Returns: {
          comment: string | null
          created_at: string
          destination_location_id: string | null
          id: string
          movement_type: string | null
          product_id: string
          quantity: number
          reason: string | null
          reference_id: string | null
          reference_type: string | null
          source_location_id: string | null
          stock_after: number | null
          stock_before: number | null
          type: string
          user_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "stock_movements"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      gama_returns_action: {
        Args: { p_action: string; p_data?: Json }
        Returns: Json
      }
      gama_sales_action: {
        Args: { p_action: string; p_data: Json }
        Returns: Json
      }
      gama_stock_adjust: {
        Args: {
          p_comment?: string
          p_delta?: number
          p_location_id: string
          p_product_id: string
          p_reason?: string
          p_reference_id?: string
          p_reference_type?: string
          p_target_quantity?: number
        }
        Returns: {
          comment: string | null
          created_at: string
          destination_location_id: string | null
          id: string
          movement_type: string | null
          product_id: string
          quantity: number
          reason: string | null
          reference_id: string | null
          reference_type: string | null
          source_location_id: string | null
          stock_after: number | null
          stock_before: number | null
          type: string
          user_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "stock_movements"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      gama_stock_reserve: {
        Args: {
          p_location_id: string
          p_product_id: string
          p_quantity: number
          p_reference_id?: string
          p_reference_type?: string
        }
        Returns: {
          created_at: string
          created_by: string | null
          id: string
          location_id: string
          product_id: string
          quantity: number
          reference_id: string | null
          reference_type: string | null
          released_at: string | null
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "stock_reservations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      gama_stock_transfer: {
        Args: {
          p_comment?: string
          p_destination_location_id: string
          p_product_id: string
          p_quantity: number
          p_reason?: string
          p_source_location_id: string
        }
        Returns: {
          comment: string | null
          created_at: string
          destination_location_id: string | null
          id: string
          movement_type: string | null
          product_id: string
          quantity: number
          reason: string | null
          reference_id: string | null
          reference_type: string | null
          source_location_id: string | null
          stock_after: number | null
          stock_before: number | null
          type: string
          user_id: string | null
        }
        SetofOptions: {
          from: "*"
          to: "stock_movements"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      gama_stock_unreserve: {
        Args: { p_consumed?: boolean; p_reservation_id: string }
        Returns: {
          created_at: string
          created_by: string | null
          id: string
          location_id: string
          product_id: string
          quantity: number
          reference_id: string | null
          reference_type: string | null
          released_at: string | null
          status: string
        }
        SetofOptions: {
          from: "*"
          to: "stock_reservations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      gama_tms_resources: { Args: never; Returns: Json }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
