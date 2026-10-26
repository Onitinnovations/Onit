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
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      activity_events: {
        Row: {
          created_at: string
          created_by: string | null
          event_code: string
          id: string
          profile_id: string
          summary: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          event_code: string
          id?: string
          profile_id: string
          summary: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          event_code?: string
          id?: string
          profile_id?: string
          summary?: string
        }
        Relationships: [
          {
            foreignKeyName: "activity_events_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_events_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      cities: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          id: string
          is_operational_label: boolean
          name: string
          state_id: string
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          id?: string
          is_operational_label?: boolean
          name: string
          state_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          is_operational_label?: boolean
          name?: string
          state_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "cities_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cities_state_id_fkey"
            columns: ["state_id"]
            isOneToOne: false
            referencedRelation: "states"
            referencedColumns: ["id"]
          },
        ]
      }
      city_service_availability: {
        Row: {
          city_id: string
          created_at: string
          created_by: string | null
          effective_from: string
          effective_until: string | null
          enabled: boolean
          id: string
          service_id: string
          updated_at: string
        }
        Insert: {
          city_id: string
          created_at?: string
          created_by?: string | null
          effective_from: string
          effective_until?: string | null
          enabled?: boolean
          id?: string
          service_id: string
          updated_at?: string
        }
        Update: {
          city_id?: string
          created_at?: string
          created_by?: string | null
          effective_from?: string
          effective_until?: string | null
          enabled?: boolean
          id?: string
          service_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "city_service_availability_city_id_fkey"
            columns: ["city_id"]
            isOneToOne: false
            referencedRelation: "cities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "city_service_availability_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "city_service_availability_service_id_fkey"
            columns: ["service_id"]
            isOneToOne: false
            referencedRelation: "services"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_preferences: {
        Row: {
          channel: string
          created_at: string
          created_by: string | null
          customer_account_id: string
          enabled: boolean
          id: string
          purpose: string
          updated_at: string
        }
        Insert: {
          channel: string
          created_at?: string
          created_by?: string | null
          customer_account_id: string
          enabled?: boolean
          id?: string
          purpose: string
          updated_at?: string
        }
        Update: {
          channel?: string
          created_at?: string
          created_by?: string | null
          customer_account_id?: string
          enabled?: boolean
          id?: string
          purpose?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "communication_preferences_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "communication_preferences_customer_account_id_fkey"
            columns: ["customer_account_id"]
            isOneToOne: false
            referencedRelation: "customer_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      corporate_account_branches: {
        Row: {
          code: string
          cost_reference: string | null
          created_at: string
          created_by: string | null
          customer_account_id: string
          id: string
          organisation_id: string
          organisation_location_id: string
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          cost_reference?: string | null
          created_at?: string
          created_by?: string | null
          customer_account_id: string
          id?: string
          organisation_id: string
          organisation_location_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          cost_reference?: string | null
          created_at?: string
          created_by?: string | null
          customer_account_id?: string
          id?: string
          organisation_id?: string
          organisation_location_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "corporate_account_branches_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "corporate_account_branches_customer_account_id_organisatio_fkey"
            columns: ["customer_account_id", "organisation_id"]
            isOneToOne: false
            referencedRelation: "corporate_accounts"
            referencedColumns: ["id", "organisation_id"]
          },
          {
            foreignKeyName: "corporate_account_branches_organisation_location_id_organi_fkey"
            columns: ["organisation_location_id", "organisation_id"]
            isOneToOne: false
            referencedRelation: "organisation_locations"
            referencedColumns: ["id", "organisation_id"]
          },
        ]
      }
      corporate_accounts: {
        Row: {
          account_reference: string
          approval_status: string
          created_at: string
          created_by: string | null
          credit_terms_approved: boolean
          id: string
          organisation_id: string
          updated_at: string
        }
        Insert: {
          account_reference: string
          approval_status?: string
          created_at?: string
          created_by?: string | null
          credit_terms_approved?: boolean
          id: string
          organisation_id: string
          updated_at?: string
        }
        Update: {
          account_reference?: string
          approval_status?: string
          created_at?: string
          created_by?: string | null
          credit_terms_approved?: boolean
          id?: string
          organisation_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "corporate_accounts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "corporate_accounts_id_organisation_id_fkey"
            columns: ["id", "organisation_id"]
            isOneToOne: true
            referencedRelation: "customer_profiles"
            referencedColumns: ["id", "organisation_id"]
          },
        ]
      }
      countries: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          id: string
          name: string
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "countries_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      currencies: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          id: string
          minor_units: number
          name: string
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          id?: string
          minor_units: number
          name: string
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          minor_units?: number
          name?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "currencies_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      customer_addresses: {
        Row: {
          address_line_1: string
          address_line_2: string | null
          archived_at: string | null
          city_id: string | null
          country_id: string
          created_at: string
          created_by: string | null
          customer_account_id: string
          id: string
          is_default: boolean
          label: string
          latitude: number | null
          local_government_area_id: string | null
          longitude: number | null
          state_id: string
          updated_at: string
        }
        Insert: {
          address_line_1: string
          address_line_2?: string | null
          archived_at?: string | null
          city_id?: string | null
          country_id: string
          created_at?: string
          created_by?: string | null
          customer_account_id: string
          id?: string
          is_default?: boolean
          label: string
          latitude?: number | null
          local_government_area_id?: string | null
          longitude?: number | null
          state_id: string
          updated_at?: string
        }
        Update: {
          address_line_1?: string
          address_line_2?: string | null
          archived_at?: string | null
          city_id?: string | null
          country_id?: string
          created_at?: string
          created_by?: string | null
          customer_account_id?: string
          id?: string
          is_default?: boolean
          label?: string
          latitude?: number | null
          local_government_area_id?: string | null
          longitude?: number | null
          state_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "customer_addresses_city_id_state_id_fkey"
            columns: ["city_id", "state_id"]
            isOneToOne: false
            referencedRelation: "cities"
            referencedColumns: ["id", "state_id"]
          },
          {
            foreignKeyName: "customer_addresses_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "countries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_addresses_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_addresses_customer_account_id_fkey"
            columns: ["customer_account_id"]
            isOneToOne: false
            referencedRelation: "customer_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_addresses_local_government_area_id_state_id_fkey"
            columns: ["local_government_area_id", "state_id"]
            isOneToOne: false
            referencedRelation: "local_government_areas"
            referencedColumns: ["id", "state_id"]
          },
          {
            foreignKeyName: "customer_addresses_state_id_country_id_fkey"
            columns: ["state_id", "country_id"]
            isOneToOne: false
            referencedRelation: "states"
            referencedColumns: ["id", "country_id"]
          },
        ]
      }
      customer_consents: {
        Row: {
          created_at: string
          created_by: string | null
          customer_account_id: string
          decision: string
          evidence_reference: string
          id: string
          policy_version: string
          purpose: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          customer_account_id: string
          decision: string
          evidence_reference: string
          id?: string
          policy_version: string
          purpose: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          customer_account_id?: string
          decision?: string
          evidence_reference?: string
          id?: string
          policy_version?: string
          purpose?: string
        }
        Relationships: [
          {
            foreignKeyName: "customer_consents_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_consents_customer_account_id_fkey"
            columns: ["customer_account_id"]
            isOneToOne: false
            referencedRelation: "customer_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      customer_contacts: {
        Row: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          customer_account_id: string
          email: string | null
          id: string
          name: string
          phone: string | null
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          customer_account_id: string
          email?: string | null
          id?: string
          name: string
          phone?: string | null
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          customer_account_id?: string
          email?: string | null
          id?: string
          name?: string
          phone?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "customer_contacts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_contacts_customer_account_id_fkey"
            columns: ["customer_account_id"]
            isOneToOne: false
            referencedRelation: "customer_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      customer_documents: {
        Row: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          customer_account_id: string
          document_object_id: string
          id: string
          purpose: string
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          customer_account_id: string
          document_object_id: string
          id?: string
          purpose: string
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          customer_account_id?: string
          document_object_id?: string
          id?: string
          purpose?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "customer_documents_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_documents_customer_account_id_fkey"
            columns: ["customer_account_id"]
            isOneToOne: false
            referencedRelation: "customer_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      customer_feedback: {
        Row: {
          comment: string | null
          created_at: string
          created_by: string | null
          customer_account_id: string
          id: string
          rating: number
        }
        Insert: {
          comment?: string | null
          created_at?: string
          created_by?: string | null
          customer_account_id: string
          id?: string
          rating: number
        }
        Update: {
          comment?: string | null
          created_at?: string
          created_by?: string | null
          customer_account_id?: string
          id?: string
          rating?: number
        }
        Relationships: [
          {
            foreignKeyName: "customer_feedback_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_feedback_customer_account_id_fkey"
            columns: ["customer_account_id"]
            isOneToOne: false
            referencedRelation: "customer_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      customer_profiles: {
        Row: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          currency_id: string
          id: string
          individual_profile_id: string | null
          organisation_id: string | null
          status: string
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          currency_id: string
          id?: string
          individual_profile_id?: string | null
          organisation_id?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          currency_id?: string
          id?: string
          individual_profile_id?: string | null
          organisation_id?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "customer_profiles_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_profiles_currency_id_fkey"
            columns: ["currency_id"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_profiles_individual_profile_id_fkey"
            columns: ["individual_profile_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_profiles_organisation_id_fkey"
            columns: ["organisation_id"]
            isOneToOne: true
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      local_government_areas: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          id: string
          name: string
          state_id: string
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          state_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          state_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "local_government_areas_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "local_government_areas_state_id_fkey"
            columns: ["state_id"]
            isOneToOne: false
            referencedRelation: "states"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_preferences: {
        Row: {
          channel: string
          created_at: string
          created_by: string | null
          enabled: boolean
          event_code: string
          id: string
          profile_id: string
          updated_at: string
        }
        Insert: {
          channel: string
          created_at?: string
          created_by?: string | null
          enabled?: boolean
          event_code: string
          id?: string
          profile_id: string
          updated_at?: string
        }
        Update: {
          channel?: string
          created_at?: string
          created_by?: string | null
          enabled?: boolean
          event_code?: string
          id?: string
          profile_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_preferences_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_preferences_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      organisation_locations: {
        Row: {
          address_text: string
          archived_at: string | null
          city_id: string | null
          code: string
          created_at: string
          created_by: string | null
          id: string
          name: string
          organisation_id: string
          updated_at: string
        }
        Insert: {
          address_text: string
          archived_at?: string | null
          city_id?: string | null
          code: string
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          organisation_id: string
          updated_at?: string
        }
        Update: {
          address_text?: string
          archived_at?: string | null
          city_id?: string | null
          code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          organisation_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organisation_locations_city_id_fkey"
            columns: ["city_id"]
            isOneToOne: false
            referencedRelation: "cities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organisation_locations_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organisation_locations_organisation_id_fkey"
            columns: ["organisation_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
        ]
      }
      organisations: {
        Row: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          id: string
          name: string
          organisation_type: string
          registration_reference: string | null
          status: string
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          organisation_type: string
          registration_reference?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          organisation_type?: string
          registration_reference?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organisations_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          display_name: string
          id: string
          status: string
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          display_name?: string
          id: string
          status?: string
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          display_name?: string
          id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "profiles_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      quotation_line_items: {
        Row: {
          created_at: string
          created_by: string
          description: string
          discount: number
          gross: number
          id: string
          kind: string
          money_scale: number
          position: number
          quantity: number
          quotation_version_id: string
          tax: number
          tax_label: string | null
          tax_rate: number
          tax_rule_id: string | null
          total: number
          unit_price: number
        }
        Insert: {
          created_at?: string
          created_by: string
          description: string
          discount: number
          gross: number
          id?: string
          kind: string
          money_scale?: number
          position: number
          quantity: number
          quotation_version_id: string
          tax: number
          tax_label?: string | null
          tax_rate: number
          tax_rule_id?: string | null
          total: number
          unit_price: number
        }
        Update: {
          created_at?: string
          created_by?: string
          description?: string
          discount?: number
          gross?: number
          id?: string
          kind?: string
          money_scale?: number
          position?: number
          quantity?: number
          quotation_version_id?: string
          tax?: number
          tax_label?: string | null
          tax_rate?: number
          tax_rule_id?: string | null
          total?: number
          unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: "quotation_line_items_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotation_line_items_quotation_version_id_fkey"
            columns: ["quotation_version_id"]
            isOneToOne: false
            referencedRelation: "quotation_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotation_line_scale_fk"
            columns: ["quotation_version_id", "money_scale"]
            isOneToOne: false
            referencedRelation: "quotation_versions"
            referencedColumns: ["id", "money_scale"]
          },
        ]
      }
      quotation_versions: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          created_at: string
          created_by: string
          currency_id: string
          decided_at: string | null
          decided_by: string | null
          discount_total: number
          id: string
          money_scale: number
          pricing_mode: string
          quotation_id: string
          request_revision: number
          status: string
          subtotal: number
          tax_total: number
          terms: string
          total: number
          updated_at: string
          valid_until: string
          version: number
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          created_by: string
          currency_id: string
          decided_at?: string | null
          decided_by?: string | null
          discount_total: number
          id?: string
          money_scale?: number
          pricing_mode: string
          quotation_id: string
          request_revision: number
          status?: string
          subtotal: number
          tax_total: number
          terms: string
          total: number
          updated_at?: string
          valid_until: string
          version: number
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          created_by?: string
          currency_id?: string
          decided_at?: string | null
          decided_by?: string | null
          discount_total?: number
          id?: string
          money_scale?: number
          pricing_mode?: string
          quotation_id?: string
          request_revision?: number
          status?: string
          subtotal?: number
          tax_total?: number
          terms?: string
          total?: number
          updated_at?: string
          valid_until?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "quotation_versions_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotation_versions_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotation_versions_currency_id_fkey"
            columns: ["currency_id"]
            isOneToOne: false
            referencedRelation: "currencies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotation_versions_decided_by_fkey"
            columns: ["decided_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotation_versions_quotation_id_fkey"
            columns: ["quotation_id"]
            isOneToOne: false
            referencedRelation: "quotations"
            referencedColumns: ["id"]
          },
        ]
      }
      quotations: {
        Row: {
          created_at: string
          created_by: string
          id: string
          reference: string
          request_id: string
        }
        Insert: {
          created_at?: string
          created_by: string
          id?: string
          reference?: string
          request_id: string
        }
        Update: {
          created_at?: string
          created_by?: string
          id?: string
          reference?: string
          request_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "quotations_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotations_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: true
            referencedRelation: "service_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      request_attachments: {
        Row: {
          created_at: string
          created_by: string
          customer_account_id: string
          document_object_id: string
          id: string
          request_id: string
        }
        Insert: {
          created_at?: string
          created_by: string
          customer_account_id: string
          document_object_id: string
          id?: string
          request_id: string
        }
        Update: {
          created_at?: string
          created_by?: string
          customer_account_id?: string
          document_object_id?: string
          id?: string
          request_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "request_attachments_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "request_attachments_request_id_customer_account_id_fkey"
            columns: ["request_id", "customer_account_id"]
            isOneToOne: false
            referencedRelation: "service_requests"
            referencedColumns: ["id", "customer_account_id"]
          },
        ]
      }
      request_history: {
        Row: {
          action: string
          actor_id: string
          created_at: string
          id: string
          request_id: string
          revision: number
        }
        Insert: {
          action: string
          actor_id: string
          created_at?: string
          id?: string
          request_id: string
          revision: number
        }
        Update: {
          action?: string
          actor_id?: string
          created_at?: string
          id?: string
          request_id?: string
          revision?: number
        }
        Relationships: [
          {
            foreignKeyName: "request_history_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "request_history_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "service_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      service_areas: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          id: string
          name: string
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_areas_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      service_booking_field_dependencies: {
        Row: {
          comparison_value: Json | null
          condition_group: number
          created_at: string
          created_by: string | null
          depends_on_field_id: string
          field_id: string
          id: string
          operator: string
          schema_id: string
          service_version_id: string
          updated_at: string
        }
        Insert: {
          comparison_value?: Json | null
          condition_group?: number
          created_at?: string
          created_by?: string | null
          depends_on_field_id: string
          field_id: string
          id?: string
          operator: string
          schema_id: string
          service_version_id: string
          updated_at?: string
        }
        Update: {
          comparison_value?: Json | null
          condition_group?: number
          created_at?: string
          created_by?: string | null
          depends_on_field_id?: string
          field_id?: string
          id?: string
          operator?: string
          schema_id?: string
          service_version_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_booking_field_depende_depends_on_field_id_schema_i_fkey"
            columns: ["depends_on_field_id", "schema_id", "service_version_id"]
            isOneToOne: false
            referencedRelation: "service_booking_fields"
            referencedColumns: ["id", "schema_id", "service_version_id"]
          },
          {
            foreignKeyName: "service_booking_field_depende_field_id_schema_id_service_v_fkey"
            columns: ["field_id", "schema_id", "service_version_id"]
            isOneToOne: false
            referencedRelation: "service_booking_fields"
            referencedColumns: ["id", "schema_id", "service_version_id"]
          },
          {
            foreignKeyName: "service_booking_field_dependencies_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      service_booking_field_groups: {
        Row: {
          created_at: string
          created_by: string | null
          group_key: string
          id: string
          label: string
          maximum_occurrences: number
          minimum_occurrences: number
          position: number
          repeatable: boolean
          schema_id: string
          service_version_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          group_key: string
          id?: string
          label: string
          maximum_occurrences?: number
          minimum_occurrences?: number
          position: number
          repeatable?: boolean
          schema_id: string
          service_version_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          group_key?: string
          id?: string
          label?: string
          maximum_occurrences?: number
          minimum_occurrences?: number
          position?: number
          repeatable?: boolean
          schema_id?: string
          service_version_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_booking_field_groups_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_booking_field_groups_schema_id_service_version_id_fkey"
            columns: ["schema_id", "service_version_id"]
            isOneToOne: false
            referencedRelation: "service_booking_schemas"
            referencedColumns: ["id", "service_version_id"]
          },
        ]
      }
      service_booking_field_options: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          field_id: string
          id: string
          label: string
          service_version_id: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          field_id: string
          id?: string
          label: string
          service_version_id: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          field_id?: string
          id?: string
          label?: string
          service_version_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_booking_field_options_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_booking_field_options_field_id_service_version_id_fkey"
            columns: ["field_id", "service_version_id"]
            isOneToOne: false
            referencedRelation: "service_booking_fields"
            referencedColumns: ["id", "service_version_id"]
          },
        ]
      }
      service_booking_field_validation_rules: {
        Row: {
          created_at: string
          created_by: string | null
          error_message: string
          field_id: string
          id: string
          rule_type: string
          rule_value: number
          schema_id: string
          service_version_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          error_message: string
          field_id: string
          id?: string
          rule_type: string
          rule_value: number
          schema_id: string
          service_version_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          error_message?: string
          field_id?: string
          id?: string
          rule_type?: string
          rule_value?: number
          schema_id?: string
          service_version_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_booking_field_validat_field_id_schema_id_service_v_fkey"
            columns: ["field_id", "schema_id", "service_version_id"]
            isOneToOne: false
            referencedRelation: "service_booking_fields"
            referencedColumns: ["id", "schema_id", "service_version_id"]
          },
          {
            foreignKeyName: "service_booking_field_validation_rules_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      service_booking_fields: {
        Row: {
          created_at: string
          created_by: string | null
          field_key: string
          field_type: string
          group_id: string
          id: string
          label: string
          position: number
          required: boolean
          schema_id: string
          service_version_id: string
          updated_at: string
          visibility: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          field_key: string
          field_type: string
          group_id: string
          id?: string
          label: string
          position: number
          required?: boolean
          schema_id: string
          service_version_id: string
          updated_at?: string
          visibility?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          field_key?: string
          field_type?: string
          group_id?: string
          id?: string
          label?: string
          position?: number
          required?: boolean
          schema_id?: string
          service_version_id?: string
          updated_at?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "booking_fields_group_fk"
            columns: ["group_id", "schema_id", "service_version_id"]
            isOneToOne: false
            referencedRelation: "service_booking_field_groups"
            referencedColumns: ["id", "schema_id", "service_version_id"]
          },
          {
            foreignKeyName: "service_booking_fields_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_booking_fields_service_version_id_fkey"
            columns: ["service_version_id"]
            isOneToOne: false
            referencedRelation: "service_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      service_booking_forms: {
        Row: {
          archived_at: string | null
          code: string
          created_at: string
          created_by: string | null
          id: string
          name: string
          service_id: string
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          code: string
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          service_id: string
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          service_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_booking_forms_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_booking_forms_service_id_fkey"
            columns: ["service_id"]
            isOneToOne: false
            referencedRelation: "services"
            referencedColumns: ["id"]
          },
        ]
      }
      service_booking_schemas: {
        Row: {
          created_at: string
          created_by: string | null
          effective_from: string | null
          effective_until: string | null
          form_id: string
          id: string
          service_id: string
          service_version_id: string
          status: string
          updated_at: string
          version: number
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          effective_from?: string | null
          effective_until?: string | null
          form_id: string
          id?: string
          service_id: string
          service_version_id: string
          status?: string
          updated_at?: string
          version: number
        }
        Update: {
          created_at?: string
          created_by?: string | null
          effective_from?: string | null
          effective_until?: string | null
          form_id?: string
          id?: string
          service_id?: string
          service_version_id?: string
          status?: string
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "service_booking_schemas_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_booking_schemas_form_id_service_id_fkey"
            columns: ["form_id", "service_id"]
            isOneToOne: false
            referencedRelation: "service_booking_forms"
            referencedColumns: ["id", "service_id"]
          },
          {
            foreignKeyName: "service_booking_schemas_service_version_id_service_id_fkey"
            columns: ["service_version_id", "service_id"]
            isOneToOne: false
            referencedRelation: "service_versions"
            referencedColumns: ["id", "service_id"]
          },
        ]
      }
      service_checklist_items: {
        Row: {
          checklist_id: string
          created_at: string
          created_by: string | null
          id: string
          item_key: string
          label: string
          position: number
          required: boolean
          service_version_id: string
          updated_at: string
        }
        Insert: {
          checklist_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          item_key: string
          label: string
          position: number
          required?: boolean
          service_version_id: string
          updated_at?: string
        }
        Update: {
          checklist_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          item_key?: string
          label?: string
          position?: number
          required?: boolean
          service_version_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_checklist_items_checklist_id_service_version_id_fkey"
            columns: ["checklist_id", "service_version_id"]
            isOneToOne: false
            referencedRelation: "service_checklists"
            referencedColumns: ["id", "service_version_id"]
          },
          {
            foreignKeyName: "service_checklist_items_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      service_checklists: {
        Row: {
          checklist_type: string
          code: string
          created_at: string
          created_by: string | null
          id: string
          name: string
          service_version_id: string
          updated_at: string
        }
        Insert: {
          checklist_type: string
          code: string
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          service_version_id: string
          updated_at?: string
        }
        Update: {
          checklist_type?: string
          code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          service_version_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_checklists_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_checklists_service_version_id_fkey"
            columns: ["service_version_id"]
            isOneToOne: false
            referencedRelation: "service_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      service_exclusions: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          description: string
          id: string
          service_version_id: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          description: string
          id?: string
          service_version_id: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          description?: string
          id?: string
          service_version_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_exclusions_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_exclusions_service_version_id_fkey"
            columns: ["service_version_id"]
            isOneToOne: false
            referencedRelation: "service_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      service_families: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          id: string
          name: string
          service_area_id: string
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          service_area_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          service_area_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_families_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_families_service_area_id_fkey"
            columns: ["service_area_id"]
            isOneToOne: false
            referencedRelation: "service_areas"
            referencedColumns: ["id"]
          },
        ]
      }
      service_faqs: {
        Row: {
          answer: string
          created_at: string
          created_by: string | null
          id: string
          position: number
          question: string
          service_version_id: string
          updated_at: string
        }
        Insert: {
          answer: string
          created_at?: string
          created_by?: string | null
          id?: string
          position: number
          question: string
          service_version_id: string
          updated_at?: string
        }
        Update: {
          answer?: string
          created_at?: string
          created_by?: string | null
          id?: string
          position?: number
          question?: string
          service_version_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_faqs_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_faqs_service_version_id_fkey"
            columns: ["service_version_id"]
            isOneToOne: false
            referencedRelation: "service_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      service_locations: {
        Row: {
          address_snapshot: string
          city_id: string | null
          country_id: string
          created_at: string
          created_by: string | null
          customer_account_id: string
          id: string
          latitude: number | null
          longitude: number | null
          source_address_id: string | null
          state_id: string
        }
        Insert: {
          address_snapshot: string
          city_id?: string | null
          country_id: string
          created_at?: string
          created_by?: string | null
          customer_account_id: string
          id?: string
          latitude?: number | null
          longitude?: number | null
          source_address_id?: string | null
          state_id: string
        }
        Update: {
          address_snapshot?: string
          city_id?: string | null
          country_id?: string
          created_at?: string
          created_by?: string | null
          customer_account_id?: string
          id?: string
          latitude?: number | null
          longitude?: number | null
          source_address_id?: string | null
          state_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_locations_city_id_state_id_fkey"
            columns: ["city_id", "state_id"]
            isOneToOne: false
            referencedRelation: "cities"
            referencedColumns: ["id", "state_id"]
          },
          {
            foreignKeyName: "service_locations_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "countries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_locations_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_locations_customer_account_id_fkey"
            columns: ["customer_account_id"]
            isOneToOne: false
            referencedRelation: "customer_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_locations_source_address_id_customer_account_id_fkey"
            columns: ["source_address_id", "customer_account_id"]
            isOneToOne: false
            referencedRelation: "customer_addresses"
            referencedColumns: ["id", "customer_account_id"]
          },
          {
            foreignKeyName: "service_locations_state_id_country_id_fkey"
            columns: ["state_id", "country_id"]
            isOneToOne: false
            referencedRelation: "states"
            referencedColumns: ["id", "country_id"]
          },
        ]
      }
      service_media: {
        Row: {
          alt_text: string
          created_at: string
          created_by: string | null
          document_object_id: string
          id: string
          position: number
          service_version_id: string
          updated_at: string
        }
        Insert: {
          alt_text: string
          created_at?: string
          created_by?: string | null
          document_object_id: string
          id?: string
          position: number
          service_version_id: string
          updated_at?: string
        }
        Update: {
          alt_text?: string
          created_at?: string
          created_by?: string | null
          document_object_id?: string
          id?: string
          position?: number
          service_version_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_media_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_media_service_version_id_fkey"
            columns: ["service_version_id"]
            isOneToOne: false
            referencedRelation: "service_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      service_option_values: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          id: string
          label: string
          option_id: string
          service_version_id: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          id?: string
          label: string
          option_id: string
          service_version_id: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          label?: string
          option_id?: string
          service_version_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_option_values_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_option_values_option_id_service_version_id_fkey"
            columns: ["option_id", "service_version_id"]
            isOneToOne: false
            referencedRelation: "service_options"
            referencedColumns: ["id", "service_version_id"]
          },
        ]
      }
      service_options: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          id: string
          name: string
          required: boolean
          service_version_id: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          required?: boolean
          service_version_id: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          required?: boolean
          service_version_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_options_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_options_service_version_id_fkey"
            columns: ["service_version_id"]
            isOneToOne: false
            referencedRelation: "service_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      service_requests: {
        Row: {
          answers: Json
          booking_schema_id: string
          branch_id: string | null
          cancelled_at: string | null
          created_at: string
          created_by: string
          customer_account_id: string
          department_id: string | null
          id: string
          instructions: string
          organisation_id: string | null
          preferred_end: string | null
          preferred_start: string | null
          reference: string
          reviewed_at: string | null
          revision: number
          service_id: string
          service_location_id: string
          service_version_id: string
          status: string
          submitted_at: string | null
          updated_at: string
        }
        Insert: {
          answers?: Json
          booking_schema_id: string
          branch_id?: string | null
          cancelled_at?: string | null
          created_at?: string
          created_by: string
          customer_account_id: string
          department_id?: string | null
          id?: string
          instructions?: string
          organisation_id?: string | null
          preferred_end?: string | null
          preferred_start?: string | null
          reference?: string
          reviewed_at?: string | null
          revision?: number
          service_id: string
          service_location_id: string
          service_version_id: string
          status?: string
          submitted_at?: string | null
          updated_at?: string
        }
        Update: {
          answers?: Json
          booking_schema_id?: string
          branch_id?: string | null
          cancelled_at?: string | null
          created_at?: string
          created_by?: string
          customer_account_id?: string
          department_id?: string | null
          id?: string
          instructions?: string
          organisation_id?: string | null
          preferred_end?: string | null
          preferred_start?: string | null
          reference?: string
          reviewed_at?: string | null
          revision?: number
          service_id?: string
          service_location_id?: string
          service_version_id?: string
          status?: string
          submitted_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_requests_booking_schema_id_service_version_id_fkey"
            columns: ["booking_schema_id", "service_version_id"]
            isOneToOne: false
            referencedRelation: "service_booking_schemas"
            referencedColumns: ["id", "service_version_id"]
          },
          {
            foreignKeyName: "service_requests_branch_id_customer_account_id_organisatio_fkey"
            columns: ["branch_id", "customer_account_id", "organisation_id"]
            isOneToOne: false
            referencedRelation: "corporate_account_branches"
            referencedColumns: ["id", "customer_account_id", "organisation_id"]
          },
          {
            foreignKeyName: "service_requests_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_requests_customer_account_id_fkey"
            columns: ["customer_account_id"]
            isOneToOne: false
            referencedRelation: "customer_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_requests_organisation_id_fkey"
            columns: ["organisation_id"]
            isOneToOne: false
            referencedRelation: "organisations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_requests_service_location_id_customer_account_id_fkey"
            columns: ["service_location_id", "customer_account_id"]
            isOneToOne: false
            referencedRelation: "service_locations"
            referencedColumns: ["id", "customer_account_id"]
          },
          {
            foreignKeyName: "service_requests_service_version_id_service_id_fkey"
            columns: ["service_version_id", "service_id"]
            isOneToOne: false
            referencedRelation: "service_versions"
            referencedColumns: ["id", "service_id"]
          },
        ]
      }
      service_requirements: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          description: string
          id: string
          required: boolean
          service_version_id: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          description: string
          id?: string
          required?: boolean
          service_version_id: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          description?: string
          id?: string
          required?: boolean
          service_version_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_requirements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_requirements_service_version_id_fkey"
            columns: ["service_version_id"]
            isOneToOne: false
            referencedRelation: "service_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      service_variants: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          id: string
          name: string
          service_version_id: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          service_version_id: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          service_version_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_variants_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_variants_service_version_id_fkey"
            columns: ["service_version_id"]
            isOneToOne: false
            referencedRelation: "service_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      service_versions: {
        Row: {
          assessment_required: boolean
          created_at: string
          created_by: string | null
          description: string
          id: string
          payment_gate: string
          pricing_mode: string
          published_at: string | null
          service_id: string
          status: string
          updated_at: string
          version: number
        }
        Insert: {
          assessment_required?: boolean
          created_at?: string
          created_by?: string | null
          description: string
          id?: string
          payment_gate?: string
          pricing_mode?: string
          published_at?: string | null
          service_id: string
          status?: string
          updated_at?: string
          version: number
        }
        Update: {
          assessment_required?: boolean
          created_at?: string
          created_by?: string | null
          description?: string
          id?: string
          payment_gate?: string
          pricing_mode?: string
          published_at?: string | null
          service_id?: string
          status?: string
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "service_versions_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_versions_service_id_fkey"
            columns: ["service_id"]
            isOneToOne: false
            referencedRelation: "services"
            referencedColumns: ["id"]
          },
        ]
      }
      service_zones: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          id: string
          name: string
          state_id: string
          status: string
          timezone: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          state_id: string
          status?: string
          timezone?: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          state_id?: string
          status?: string
          timezone?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_zones_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_zones_state_id_fkey"
            columns: ["state_id"]
            isOneToOne: false
            referencedRelation: "states"
            referencedColumns: ["id"]
          },
        ]
      }
      services: {
        Row: {
          code: string
          created_at: string
          created_by: string | null
          id: string
          name: string
          service_family_id: string
          slug: string
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          service_family_id: string
          slug: string
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          service_family_id?: string
          slug?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "services_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "services_service_family_id_fkey"
            columns: ["service_family_id"]
            isOneToOne: false
            referencedRelation: "service_families"
            referencedColumns: ["id"]
          },
        ]
      }
      states: {
        Row: {
          code: string
          country_id: string
          created_at: string
          created_by: string | null
          id: string
          name: string
          status: string
          updated_at: string
        }
        Insert: {
          code: string
          country_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          status?: string
          updated_at?: string
        }
        Update: {
          code?: string
          country_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "states_country_id_fkey"
            columns: ["country_id"]
            isOneToOne: false
            referencedRelation: "countries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "states_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      support_messages: {
        Row: {
          body: string
          created_at: string
          created_by: string | null
          customer_account_id: string
          id: string
          ticket_id: string
          visibility: string
        }
        Insert: {
          body: string
          created_at?: string
          created_by?: string | null
          customer_account_id: string
          id?: string
          ticket_id: string
          visibility?: string
        }
        Update: {
          body?: string
          created_at?: string
          created_by?: string | null
          customer_account_id?: string
          id?: string
          ticket_id?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "support_messages_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "support_messages_ticket_id_customer_account_id_fkey"
            columns: ["ticket_id", "customer_account_id"]
            isOneToOne: false
            referencedRelation: "support_tickets"
            referencedColumns: ["id", "customer_account_id"]
          },
        ]
      }
      support_tickets: {
        Row: {
          closed_at: string | null
          created_at: string
          created_by: string | null
          customer_account_id: string
          id: string
          status: string
          subject: string
          updated_at: string
        }
        Insert: {
          closed_at?: string | null
          created_at?: string
          created_by?: string | null
          customer_account_id: string
          id?: string
          status?: string
          subject: string
          updated_at?: string
        }
        Update: {
          closed_at?: string | null
          created_at?: string
          created_by?: string | null
          customer_account_id?: string
          id?: string
          status?: string
          subject?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "support_tickets_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "support_tickets_customer_account_id_fkey"
            columns: ["customer_account_id"]
            isOneToOne: false
            referencedRelation: "customer_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      user_preferences: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          locale: string
          profile_id: string
          timezone: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          locale?: string
          profile_id: string
          timezone?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          locale?: string
          profile_id?: string
          timezone?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_preferences_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_preferences_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      add_customer_address: {
        Args: {
          p_account_id: string
          p_address: string
          p_city_id?: string
          p_country_id: string
          p_label: string
          p_state_id: string
        }
        Returns: string
      }
      approve_pricing_card: { Args: { p_id: string }; Returns: string }
      assessment_command: {
        Args: { p_action: string; p_data: Json; p_request: string }
        Returns: string
      }
      attach_request_document: {
        Args: { p_document: string; p_id: string }
        Returns: string
      }
      change_service_request: {
        Args: {
          p_action: string
          p_answers?: Json
          p_end?: string
          p_id: string
          p_instructions?: string
          p_revision: number
          p_start?: string
        }
        Returns: number
      }
      commercial_policy: {
        Args: { p_action: string; p_data: Json }
        Returns: string
      }
      create_pricing_card: {
        Args: { p_config: Json; p_rules: Json }
        Returns: string
      }
      create_service_request: {
        Args: {
          p_account: string
          p_address: string
          p_answers: Json
          p_branch?: string
          p_department?: string
          p_end?: string
          p_instructions?: string
          p_key: string
          p_start?: string
          p_version: string
        }
        Returns: string
      }
      decide_quotation: {
        Args: { p_action: string; p_id: string }
        Returns: string
      }
      ensure_individual_customer: { Args: never; Returns: string }
      generate_quotation: {
        Args: { p_input: Json; p_key: string; p_request: string }
        Returns: string
      }
      prepare_customer_upload: {
        Args: {
          p_account_id: string
          p_byte_size: number
          p_content_type: string
        }
        Returns: Json
      }
      prepare_quotation: {
        Args: {
          p_currency: string
          p_key: string
          p_lines: Json
          p_request: string
          p_terms: string
          p_valid_until: string
        }
        Returns: string
      }
      read_assessment: { Args: { p_id: string }; Returns: Json }
      read_pricing_card: { Args: { p_id: string }; Returns: Json }
      read_quotation: { Args: { p_id: string }; Returns: Json }
      read_quotation_commercial: { Args: { p_id: string }; Returns: Json }
      retire_pricing_card: {
        Args: { p_id: string; p_key: string; p_reason: string }
        Returns: string
      }
      review_service_request: {
        Args: { p_id: string; p_revision: number }
        Returns: number
      }
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
