// GENERATED from tested native PostgreSQL 17.11 operational candidate; not hosted catalogs, not hosted Supabase.
// Regenerate: node scripts/database/generate-orders-types.mjs. Prefer official Supabase CLI output after deployment.
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Database = {
  public: {
    Tables: {
      "activity_events": {
        Row: {
          "id": string;
          "profile_id": string;
          "event_code": string;
          "summary": string;
          "created_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "profile_id": string;
          "event_code": string;
          "summary": string;
          "created_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "profile_id"?: string;
          "event_code"?: string;
          "summary"?: string;
          "created_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "activity_events_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "activity_events_profile_id_fkey"; columns: ["profile_id"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
        ];
      };
      "cities": {
        Row: {
          "id": string;
          "state_id": string;
          "code": string;
          "name": string;
          "is_operational_label": boolean;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
          "status": string;
        };
        Insert: {
          "id"?: string;
          "state_id": string;
          "code": string;
          "name": string;
          "is_operational_label"?: boolean;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
          "status"?: string;
        };
        Update: {
          "id"?: string;
          "state_id"?: string;
          "code"?: string;
          "name"?: string;
          "is_operational_label"?: boolean;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
          "status"?: string;
        };
        Relationships: [
          { foreignKeyName: "cities_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "cities_state_id_fkey"; columns: ["state_id"]; isOneToOne: false; referencedRelation: "states"; referencedColumns: ["id"] },
        ];
      };
      "city_service_availability": {
        Row: {
          "id": string;
          "service_id": string;
          "city_id": string;
          "enabled": boolean;
          "effective_from": string;
          "effective_until": string | null;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "service_id": string;
          "city_id": string;
          "enabled"?: boolean;
          "effective_from": string;
          "effective_until"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "service_id"?: string;
          "city_id"?: string;
          "enabled"?: boolean;
          "effective_from"?: string;
          "effective_until"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "city_service_availability_city_id_fkey"; columns: ["city_id"]; isOneToOne: false; referencedRelation: "cities"; referencedColumns: ["id"] },
          { foreignKeyName: "city_service_availability_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "city_service_availability_service_id_fkey"; columns: ["service_id"]; isOneToOne: false; referencedRelation: "services"; referencedColumns: ["id"] },
        ];
      };
      "communication_preferences": {
        Row: {
          "id": string;
          "customer_account_id": string;
          "channel": string;
          "purpose": string;
          "enabled": boolean;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "customer_account_id": string;
          "channel": string;
          "purpose": string;
          "enabled"?: boolean;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "customer_account_id"?: string;
          "channel"?: string;
          "purpose"?: string;
          "enabled"?: boolean;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "communication_preferences_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "communication_preferences_customer_account_id_fkey"; columns: ["customer_account_id"]; isOneToOne: false; referencedRelation: "customer_profiles"; referencedColumns: ["id"] },
        ];
      };
      "corporate_account_branches": {
        Row: {
          "id": string;
          "customer_account_id": string;
          "organisation_id": string;
          "organisation_location_id": string;
          "code": string;
          "cost_reference": string | null;
          "status": string;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "customer_account_id": string;
          "organisation_id": string;
          "organisation_location_id": string;
          "code": string;
          "cost_reference"?: string | null;
          "status"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "customer_account_id"?: string;
          "organisation_id"?: string;
          "organisation_location_id"?: string;
          "code"?: string;
          "cost_reference"?: string | null;
          "status"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "corporate_account_branches_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "corporate_account_branches_customer_account_id_organisatio_fkey"; columns: ["customer_account_id","organisation_id"]; isOneToOne: false; referencedRelation: "corporate_accounts"; referencedColumns: ["id","organisation_id"] },
          { foreignKeyName: "corporate_account_branches_organisation_location_id_organi_fkey"; columns: ["organisation_location_id","organisation_id"]; isOneToOne: false; referencedRelation: "organisation_locations"; referencedColumns: ["id","organisation_id"] },
        ];
      };
      "corporate_accounts": {
        Row: {
          "id": string;
          "organisation_id": string;
          "approval_status": string;
          "account_reference": string;
          "credit_terms_approved": boolean;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id": string;
          "organisation_id": string;
          "approval_status"?: string;
          "account_reference": string;
          "credit_terms_approved"?: boolean;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "organisation_id"?: string;
          "approval_status"?: string;
          "account_reference"?: string;
          "credit_terms_approved"?: boolean;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "corporate_accounts_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "corporate_accounts_id_organisation_id_fkey"; columns: ["id","organisation_id"]; isOneToOne: true; referencedRelation: "customer_profiles"; referencedColumns: ["id","organisation_id"] },
        ];
      };
      "countries": {
        Row: {
          "id": string;
          "code": string;
          "name": string;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
          "status": string;
        };
        Insert: {
          "id"?: string;
          "code": string;
          "name": string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
          "status"?: string;
        };
        Update: {
          "id"?: string;
          "code"?: string;
          "name"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
          "status"?: string;
        };
        Relationships: [
          { foreignKeyName: "countries_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
        ];
      };
      "currencies": {
        Row: {
          "id": string;
          "code": string;
          "name": string;
          "minor_units": number;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
          "status": string;
        };
        Insert: {
          "id"?: string;
          "code": string;
          "name": string;
          "minor_units": number;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
          "status"?: string;
        };
        Update: {
          "id"?: string;
          "code"?: string;
          "name"?: string;
          "minor_units"?: number;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
          "status"?: string;
        };
        Relationships: [
          { foreignKeyName: "currencies_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
        ];
      };
      "customer_addresses": {
        Row: {
          "id": string;
          "customer_account_id": string;
          "label": string;
          "address_line_1": string;
          "address_line_2": string | null;
          "country_id": string;
          "state_id": string;
          "city_id": string | null;
          "local_government_area_id": string | null;
          "latitude": number | null;
          "longitude": number | null;
          "is_default": boolean;
          "archived_at": string | null;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "customer_account_id": string;
          "label": string;
          "address_line_1": string;
          "address_line_2"?: string | null;
          "country_id": string;
          "state_id": string;
          "city_id"?: string | null;
          "local_government_area_id"?: string | null;
          "latitude"?: number | null;
          "longitude"?: number | null;
          "is_default"?: boolean;
          "archived_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "customer_account_id"?: string;
          "label"?: string;
          "address_line_1"?: string;
          "address_line_2"?: string | null;
          "country_id"?: string;
          "state_id"?: string;
          "city_id"?: string | null;
          "local_government_area_id"?: string | null;
          "latitude"?: number | null;
          "longitude"?: number | null;
          "is_default"?: boolean;
          "archived_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "customer_addresses_city_id_state_id_fkey"; columns: ["city_id","state_id"]; isOneToOne: false; referencedRelation: "cities"; referencedColumns: ["id","state_id"] },
          { foreignKeyName: "customer_addresses_country_id_fkey"; columns: ["country_id"]; isOneToOne: false; referencedRelation: "countries"; referencedColumns: ["id"] },
          { foreignKeyName: "customer_addresses_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "customer_addresses_customer_account_id_fkey"; columns: ["customer_account_id"]; isOneToOne: false; referencedRelation: "customer_profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "customer_addresses_local_government_area_id_state_id_fkey"; columns: ["local_government_area_id","state_id"]; isOneToOne: false; referencedRelation: "local_government_areas"; referencedColumns: ["id","state_id"] },
          { foreignKeyName: "customer_addresses_state_id_country_id_fkey"; columns: ["state_id","country_id"]; isOneToOne: false; referencedRelation: "states"; referencedColumns: ["id","country_id"] },
        ];
      };
      "customer_consents": {
        Row: {
          "id": string;
          "customer_account_id": string;
          "purpose": string;
          "policy_version": string;
          "decision": string;
          "evidence_reference": string;
          "created_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "customer_account_id": string;
          "purpose": string;
          "policy_version": string;
          "decision": string;
          "evidence_reference": string;
          "created_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "customer_account_id"?: string;
          "purpose"?: string;
          "policy_version"?: string;
          "decision"?: string;
          "evidence_reference"?: string;
          "created_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "customer_consents_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "customer_consents_customer_account_id_fkey"; columns: ["customer_account_id"]; isOneToOne: false; referencedRelation: "customer_profiles"; referencedColumns: ["id"] },
        ];
      };
      "customer_contacts": {
        Row: {
          "id": string;
          "customer_account_id": string;
          "name": string;
          "email": string | null;
          "phone": string | null;
          "archived_at": string | null;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "customer_account_id": string;
          "name": string;
          "email"?: string | null;
          "phone"?: string | null;
          "archived_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "customer_account_id"?: string;
          "name"?: string;
          "email"?: string | null;
          "phone"?: string | null;
          "archived_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "customer_contacts_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "customer_contacts_customer_account_id_fkey"; columns: ["customer_account_id"]; isOneToOne: false; referencedRelation: "customer_profiles"; referencedColumns: ["id"] },
        ];
      };
      "customer_documents": {
        Row: {
          "id": string;
          "customer_account_id": string;
          "document_object_id": string;
          "purpose": string;
          "archived_at": string | null;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "customer_account_id": string;
          "document_object_id": string;
          "purpose": string;
          "archived_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "customer_account_id"?: string;
          "document_object_id"?: string;
          "purpose"?: string;
          "archived_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "customer_documents_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "customer_documents_customer_account_id_fkey"; columns: ["customer_account_id"]; isOneToOne: false; referencedRelation: "customer_profiles"; referencedColumns: ["id"] },
        ];
      };
      "customer_feedback": {
        Row: {
          "id": string;
          "customer_account_id": string;
          "rating": number;
          "comment": string | null;
          "created_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "customer_account_id": string;
          "rating": number;
          "comment"?: string | null;
          "created_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "customer_account_id"?: string;
          "rating"?: number;
          "comment"?: string | null;
          "created_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "customer_feedback_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "customer_feedback_customer_account_id_fkey"; columns: ["customer_account_id"]; isOneToOne: false; referencedRelation: "customer_profiles"; referencedColumns: ["id"] },
        ];
      };
      "customer_profiles": {
        Row: {
          "id": string;
          "individual_profile_id": string | null;
          "organisation_id": string | null;
          "status": string;
          "currency_id": string;
          "archived_at": string | null;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "individual_profile_id"?: string | null;
          "organisation_id"?: string | null;
          "status"?: string;
          "currency_id": string;
          "archived_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "individual_profile_id"?: string | null;
          "organisation_id"?: string | null;
          "status"?: string;
          "currency_id"?: string;
          "archived_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "customer_profiles_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "customer_profiles_currency_id_fkey"; columns: ["currency_id"]; isOneToOne: false; referencedRelation: "currencies"; referencedColumns: ["id"] },
          { foreignKeyName: "customer_profiles_individual_profile_id_fkey"; columns: ["individual_profile_id"]; isOneToOne: true; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "customer_profiles_organisation_id_fkey"; columns: ["organisation_id"]; isOneToOne: true; referencedRelation: "organisations"; referencedColumns: ["id"] },
        ];
      };
      "local_government_areas": {
        Row: {
          "id": string;
          "state_id": string;
          "code": string;
          "name": string;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
          "status": string;
        };
        Insert: {
          "id"?: string;
          "state_id": string;
          "code": string;
          "name": string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
          "status"?: string;
        };
        Update: {
          "id"?: string;
          "state_id"?: string;
          "code"?: string;
          "name"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
          "status"?: string;
        };
        Relationships: [
          { foreignKeyName: "local_government_areas_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "local_government_areas_state_id_fkey"; columns: ["state_id"]; isOneToOne: false; referencedRelation: "states"; referencedColumns: ["id"] },
        ];
      };
      "notification_preferences": {
        Row: {
          "id": string;
          "profile_id": string;
          "channel": string;
          "event_code": string;
          "enabled": boolean;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "profile_id": string;
          "channel": string;
          "event_code": string;
          "enabled"?: boolean;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "profile_id"?: string;
          "channel"?: string;
          "event_code"?: string;
          "enabled"?: boolean;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "notification_preferences_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "notification_preferences_profile_id_fkey"; columns: ["profile_id"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
        ];
      };
      "organisation_locations": {
        Row: {
          "id": string;
          "organisation_id": string;
          "code": string;
          "name": string;
          "address_text": string;
          "city_id": string | null;
          "archived_at": string | null;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "organisation_id": string;
          "code": string;
          "name": string;
          "address_text": string;
          "city_id"?: string | null;
          "archived_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "organisation_id"?: string;
          "code"?: string;
          "name"?: string;
          "address_text"?: string;
          "city_id"?: string | null;
          "archived_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "organisation_locations_city_id_fkey"; columns: ["city_id"]; isOneToOne: false; referencedRelation: "cities"; referencedColumns: ["id"] },
          { foreignKeyName: "organisation_locations_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "organisation_locations_organisation_id_fkey"; columns: ["organisation_id"]; isOneToOne: false; referencedRelation: "organisations"; referencedColumns: ["id"] },
        ];
      };
      "organisations": {
        Row: {
          "id": string;
          "name": string;
          "organisation_type": string;
          "status": string;
          "registration_reference": string | null;
          "archived_at": string | null;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "name": string;
          "organisation_type": string;
          "status"?: string;
          "registration_reference"?: string | null;
          "archived_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "name"?: string;
          "organisation_type"?: string;
          "status"?: string;
          "registration_reference"?: string | null;
          "archived_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "organisations_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
        ];
      };
      "profiles": {
        Row: {
          "id": string;
          "display_name": string;
          "status": string;
          "archived_at": string | null;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id": string;
          "display_name"?: string;
          "status"?: string;
          "archived_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "display_name"?: string;
          "status"?: string;
          "archived_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "profiles_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
        ];
      };
      "quotation_line_items": {
        Row: {
          "id": string;
          "quotation_version_id": string;
          "position": number;
          "description": string;
          "kind": string;
          "quantity": number;
          "unit_price": number;
          "discount": number;
          "tax_rule_id": string | null;
          "tax_label": string | null;
          "tax_rate": number;
          "gross": number;
          "tax": number;
          "total": number;
          "created_at": string;
          "created_by": string;
          "money_scale": number;
        };
        Insert: {
          "id"?: string;
          "quotation_version_id": string;
          "position": number;
          "description": string;
          "kind": string;
          "quantity": number;
          "unit_price": number;
          "discount": number;
          "tax_rule_id"?: string | null;
          "tax_label"?: string | null;
          "tax_rate": number;
          "gross": number;
          "tax": number;
          "total": number;
          "created_at"?: string;
          "created_by": string;
          "money_scale"?: number;
        };
        Update: {
          "id"?: string;
          "quotation_version_id"?: string;
          "position"?: number;
          "description"?: string;
          "kind"?: string;
          "quantity"?: number;
          "unit_price"?: number;
          "discount"?: number;
          "tax_rule_id"?: string | null;
          "tax_label"?: string | null;
          "tax_rate"?: number;
          "gross"?: number;
          "tax"?: number;
          "total"?: number;
          "created_at"?: string;
          "created_by"?: string;
          "money_scale"?: number;
        };
        Relationships: [
          { foreignKeyName: "quotation_line_items_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "quotation_line_items_quotation_version_id_fkey"; columns: ["quotation_version_id"]; isOneToOne: false; referencedRelation: "quotation_versions"; referencedColumns: ["id"] },
          { foreignKeyName: "quotation_line_scale_fk"; columns: ["quotation_version_id","money_scale"]; isOneToOne: false; referencedRelation: "quotation_versions"; referencedColumns: ["id","money_scale"] },
        ];
      };
      "quotation_versions": {
        Row: {
          "id": string;
          "quotation_id": string;
          "version": number;
          "request_revision": number;
          "currency_id": string;
          "pricing_mode": string;
          "status": string;
          "valid_until": string;
          "terms": string;
          "subtotal": number;
          "discount_total": number;
          "tax_total": number;
          "total": number;
          "approved_by": string | null;
          "approved_at": string | null;
          "decided_by": string | null;
          "decided_at": string | null;
          "created_at": string;
          "updated_at": string;
          "created_by": string;
          "money_scale": number;
        };
        Insert: {
          "id"?: string;
          "quotation_id": string;
          "version": number;
          "request_revision": number;
          "currency_id": string;
          "pricing_mode": string;
          "status"?: string;
          "valid_until": string;
          "terms": string;
          "subtotal": number;
          "discount_total": number;
          "tax_total": number;
          "total": number;
          "approved_by"?: string | null;
          "approved_at"?: string | null;
          "decided_by"?: string | null;
          "decided_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by": string;
          "money_scale"?: number;
        };
        Update: {
          "id"?: string;
          "quotation_id"?: string;
          "version"?: number;
          "request_revision"?: number;
          "currency_id"?: string;
          "pricing_mode"?: string;
          "status"?: string;
          "valid_until"?: string;
          "terms"?: string;
          "subtotal"?: number;
          "discount_total"?: number;
          "tax_total"?: number;
          "total"?: number;
          "approved_by"?: string | null;
          "approved_at"?: string | null;
          "decided_by"?: string | null;
          "decided_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string;
          "money_scale"?: number;
        };
        Relationships: [
          { foreignKeyName: "quotation_versions_approved_by_fkey"; columns: ["approved_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "quotation_versions_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "quotation_versions_currency_id_fkey"; columns: ["currency_id"]; isOneToOne: false; referencedRelation: "currencies"; referencedColumns: ["id"] },
          { foreignKeyName: "quotation_versions_decided_by_fkey"; columns: ["decided_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "quotation_versions_quotation_id_fkey"; columns: ["quotation_id"]; isOneToOne: false; referencedRelation: "quotations"; referencedColumns: ["id"] },
        ];
      };
      "quotations": {
        Row: {
          "id": string;
          "request_id": string;
          "reference": string;
          "created_at": string;
          "created_by": string;
        };
        Insert: {
          "id"?: string;
          "request_id": string;
          "reference"?: string;
          "created_at"?: string;
          "created_by": string;
        };
        Update: {
          "id"?: string;
          "request_id"?: string;
          "reference"?: string;
          "created_at"?: string;
          "created_by"?: string;
        };
        Relationships: [
          { foreignKeyName: "quotations_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "quotations_request_id_fkey"; columns: ["request_id"]; isOneToOne: true; referencedRelation: "service_requests"; referencedColumns: ["id"] },
        ];
      };
      "request_attachments": {
        Row: {
          "id": string;
          "request_id": string;
          "customer_account_id": string;
          "document_object_id": string;
          "created_at": string;
          "created_by": string;
        };
        Insert: {
          "id"?: string;
          "request_id": string;
          "customer_account_id": string;
          "document_object_id": string;
          "created_at"?: string;
          "created_by": string;
        };
        Update: {
          "id"?: string;
          "request_id"?: string;
          "customer_account_id"?: string;
          "document_object_id"?: string;
          "created_at"?: string;
          "created_by"?: string;
        };
        Relationships: [
          { foreignKeyName: "request_attachments_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "request_attachments_request_id_customer_account_id_fkey"; columns: ["request_id","customer_account_id"]; isOneToOne: false; referencedRelation: "service_requests"; referencedColumns: ["id","customer_account_id"] },
        ];
      };
      "request_history": {
        Row: {
          "id": string;
          "request_id": string;
          "revision": number;
          "action": string;
          "actor_id": string;
          "created_at": string;
        };
        Insert: {
          "id"?: string;
          "request_id": string;
          "revision": number;
          "action": string;
          "actor_id": string;
          "created_at"?: string;
        };
        Update: {
          "id"?: string;
          "request_id"?: string;
          "revision"?: number;
          "action"?: string;
          "actor_id"?: string;
          "created_at"?: string;
        };
        Relationships: [
          { foreignKeyName: "request_history_actor_id_fkey"; columns: ["actor_id"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "request_history_request_id_fkey"; columns: ["request_id"]; isOneToOne: false; referencedRelation: "service_requests"; referencedColumns: ["id"] },
        ];
      };
      "service_areas": {
        Row: {
          "id": string;
          "code": string;
          "name": string;
          "status": string;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "code": string;
          "name": string;
          "status"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "code"?: string;
          "name"?: string;
          "status"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_areas_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
        ];
      };
      "service_booking_field_dependencies": {
        Row: {
          "id": string;
          "schema_id": string;
          "service_version_id": string;
          "field_id": string;
          "depends_on_field_id": string;
          "condition_group": number;
          "operator": string;
          "comparison_value": Json | null;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "schema_id": string;
          "service_version_id": string;
          "field_id": string;
          "depends_on_field_id": string;
          "condition_group"?: number;
          "operator": string;
          "comparison_value"?: Json | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "schema_id"?: string;
          "service_version_id"?: string;
          "field_id"?: string;
          "depends_on_field_id"?: string;
          "condition_group"?: number;
          "operator"?: string;
          "comparison_value"?: Json | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_booking_field_depende_depends_on_field_id_schema_i_fkey"; columns: ["depends_on_field_id","schema_id","service_version_id"]; isOneToOne: false; referencedRelation: "service_booking_fields"; referencedColumns: ["id","schema_id","service_version_id"] },
          { foreignKeyName: "service_booking_field_depende_field_id_schema_id_service_v_fkey"; columns: ["field_id","schema_id","service_version_id"]; isOneToOne: false; referencedRelation: "service_booking_fields"; referencedColumns: ["id","schema_id","service_version_id"] },
          { foreignKeyName: "service_booking_field_dependencies_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
        ];
      };
      "service_booking_field_groups": {
        Row: {
          "id": string;
          "schema_id": string;
          "service_version_id": string;
          "group_key": string;
          "label": string;
          "position": number;
          "repeatable": boolean;
          "minimum_occurrences": number;
          "maximum_occurrences": number;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "schema_id": string;
          "service_version_id": string;
          "group_key": string;
          "label": string;
          "position": number;
          "repeatable"?: boolean;
          "minimum_occurrences"?: number;
          "maximum_occurrences"?: number;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "schema_id"?: string;
          "service_version_id"?: string;
          "group_key"?: string;
          "label"?: string;
          "position"?: number;
          "repeatable"?: boolean;
          "minimum_occurrences"?: number;
          "maximum_occurrences"?: number;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_booking_field_groups_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_booking_field_groups_schema_id_service_version_id_fkey"; columns: ["schema_id","service_version_id"]; isOneToOne: false; referencedRelation: "service_booking_schemas"; referencedColumns: ["id","service_version_id"] },
        ];
      };
      "service_booking_field_options": {
        Row: {
          "id": string;
          "field_id": string;
          "service_version_id": string;
          "code": string;
          "label": string;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "field_id": string;
          "service_version_id": string;
          "code": string;
          "label": string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "field_id"?: string;
          "service_version_id"?: string;
          "code"?: string;
          "label"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_booking_field_options_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_booking_field_options_field_id_service_version_id_fkey"; columns: ["field_id","service_version_id"]; isOneToOne: false; referencedRelation: "service_booking_fields"; referencedColumns: ["id","service_version_id"] },
        ];
      };
      "service_booking_field_validation_rules": {
        Row: {
          "id": string;
          "schema_id": string;
          "service_version_id": string;
          "field_id": string;
          "rule_type": string;
          "rule_value": number;
          "error_message": string;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "schema_id": string;
          "service_version_id": string;
          "field_id": string;
          "rule_type": string;
          "rule_value": number;
          "error_message": string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "schema_id"?: string;
          "service_version_id"?: string;
          "field_id"?: string;
          "rule_type"?: string;
          "rule_value"?: number;
          "error_message"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_booking_field_validat_field_id_schema_id_service_v_fkey"; columns: ["field_id","schema_id","service_version_id"]; isOneToOne: false; referencedRelation: "service_booking_fields"; referencedColumns: ["id","schema_id","service_version_id"] },
          { foreignKeyName: "service_booking_field_validation_rules_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
        ];
      };
      "service_booking_fields": {
        Row: {
          "id": string;
          "service_version_id": string;
          "field_key": string;
          "label": string;
          "field_type": string;
          "required": boolean;
          "position": number;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
          "schema_id": string;
          "group_id": string;
          "visibility": string;
        };
        Insert: {
          "id"?: string;
          "service_version_id": string;
          "field_key": string;
          "label": string;
          "field_type": string;
          "required"?: boolean;
          "position": number;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
          "schema_id": string;
          "group_id": string;
          "visibility"?: string;
        };
        Update: {
          "id"?: string;
          "service_version_id"?: string;
          "field_key"?: string;
          "label"?: string;
          "field_type"?: string;
          "required"?: boolean;
          "position"?: number;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
          "schema_id"?: string;
          "group_id"?: string;
          "visibility"?: string;
        };
        Relationships: [
          { foreignKeyName: "booking_fields_group_fk"; columns: ["group_id","schema_id","service_version_id"]; isOneToOne: false; referencedRelation: "service_booking_field_groups"; referencedColumns: ["id","schema_id","service_version_id"] },
          { foreignKeyName: "service_booking_fields_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_booking_fields_service_version_id_fkey"; columns: ["service_version_id"]; isOneToOne: false; referencedRelation: "service_versions"; referencedColumns: ["id"] },
        ];
      };
      "service_booking_forms": {
        Row: {
          "id": string;
          "service_id": string;
          "code": string;
          "name": string;
          "archived_at": string | null;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "service_id": string;
          "code": string;
          "name": string;
          "archived_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "service_id"?: string;
          "code"?: string;
          "name"?: string;
          "archived_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_booking_forms_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_booking_forms_service_id_fkey"; columns: ["service_id"]; isOneToOne: false; referencedRelation: "services"; referencedColumns: ["id"] },
        ];
      };
      "service_booking_schemas": {
        Row: {
          "id": string;
          "form_id": string;
          "service_id": string;
          "service_version_id": string;
          "version": number;
          "status": string;
          "effective_from": string | null;
          "effective_until": string | null;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "form_id": string;
          "service_id": string;
          "service_version_id": string;
          "version": number;
          "status"?: string;
          "effective_from"?: string | null;
          "effective_until"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "form_id"?: string;
          "service_id"?: string;
          "service_version_id"?: string;
          "version"?: number;
          "status"?: string;
          "effective_from"?: string | null;
          "effective_until"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_booking_schemas_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_booking_schemas_form_id_service_id_fkey"; columns: ["form_id","service_id"]; isOneToOne: false; referencedRelation: "service_booking_forms"; referencedColumns: ["id","service_id"] },
          { foreignKeyName: "service_booking_schemas_service_version_id_service_id_fkey"; columns: ["service_version_id","service_id"]; isOneToOne: false; referencedRelation: "service_versions"; referencedColumns: ["id","service_id"] },
        ];
      };
      "service_checklist_items": {
        Row: {
          "id": string;
          "checklist_id": string;
          "service_version_id": string;
          "item_key": string;
          "label": string;
          "required": boolean;
          "position": number;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "checklist_id": string;
          "service_version_id": string;
          "item_key": string;
          "label": string;
          "required"?: boolean;
          "position": number;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "checklist_id"?: string;
          "service_version_id"?: string;
          "item_key"?: string;
          "label"?: string;
          "required"?: boolean;
          "position"?: number;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_checklist_items_checklist_id_service_version_id_fkey"; columns: ["checklist_id","service_version_id"]; isOneToOne: false; referencedRelation: "service_checklists"; referencedColumns: ["id","service_version_id"] },
          { foreignKeyName: "service_checklist_items_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
        ];
      };
      "service_checklists": {
        Row: {
          "id": string;
          "service_version_id": string;
          "code": string;
          "checklist_type": string;
          "name": string;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "service_version_id": string;
          "code": string;
          "checklist_type": string;
          "name": string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "service_version_id"?: string;
          "code"?: string;
          "checklist_type"?: string;
          "name"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_checklists_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_checklists_service_version_id_fkey"; columns: ["service_version_id"]; isOneToOne: false; referencedRelation: "service_versions"; referencedColumns: ["id"] },
        ];
      };
      "service_exclusions": {
        Row: {
          "id": string;
          "service_version_id": string;
          "code": string;
          "description": string;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "service_version_id": string;
          "code": string;
          "description": string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "service_version_id"?: string;
          "code"?: string;
          "description"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_exclusions_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_exclusions_service_version_id_fkey"; columns: ["service_version_id"]; isOneToOne: false; referencedRelation: "service_versions"; referencedColumns: ["id"] },
        ];
      };
      "service_families": {
        Row: {
          "id": string;
          "service_area_id": string;
          "code": string;
          "name": string;
          "status": string;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "service_area_id": string;
          "code": string;
          "name": string;
          "status"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "service_area_id"?: string;
          "code"?: string;
          "name"?: string;
          "status"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_families_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_families_service_area_id_fkey"; columns: ["service_area_id"]; isOneToOne: false; referencedRelation: "service_areas"; referencedColumns: ["id"] },
        ];
      };
      "service_faqs": {
        Row: {
          "id": string;
          "service_version_id": string;
          "question": string;
          "answer": string;
          "position": number;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "service_version_id": string;
          "question": string;
          "answer": string;
          "position": number;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "service_version_id"?: string;
          "question"?: string;
          "answer"?: string;
          "position"?: number;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_faqs_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_faqs_service_version_id_fkey"; columns: ["service_version_id"]; isOneToOne: false; referencedRelation: "service_versions"; referencedColumns: ["id"] },
        ];
      };
      "service_locations": {
        Row: {
          "id": string;
          "customer_account_id": string;
          "source_address_id": string | null;
          "address_snapshot": string;
          "country_id": string;
          "state_id": string;
          "city_id": string | null;
          "latitude": number | null;
          "longitude": number | null;
          "created_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "customer_account_id": string;
          "source_address_id"?: string | null;
          "address_snapshot": string;
          "country_id": string;
          "state_id": string;
          "city_id"?: string | null;
          "latitude"?: number | null;
          "longitude"?: number | null;
          "created_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "customer_account_id"?: string;
          "source_address_id"?: string | null;
          "address_snapshot"?: string;
          "country_id"?: string;
          "state_id"?: string;
          "city_id"?: string | null;
          "latitude"?: number | null;
          "longitude"?: number | null;
          "created_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_locations_city_id_state_id_fkey"; columns: ["city_id","state_id"]; isOneToOne: false; referencedRelation: "cities"; referencedColumns: ["id","state_id"] },
          { foreignKeyName: "service_locations_country_id_fkey"; columns: ["country_id"]; isOneToOne: false; referencedRelation: "countries"; referencedColumns: ["id"] },
          { foreignKeyName: "service_locations_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_locations_customer_account_id_fkey"; columns: ["customer_account_id"]; isOneToOne: false; referencedRelation: "customer_profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_locations_source_address_id_customer_account_id_fkey"; columns: ["source_address_id","customer_account_id"]; isOneToOne: false; referencedRelation: "customer_addresses"; referencedColumns: ["id","customer_account_id"] },
          { foreignKeyName: "service_locations_state_id_country_id_fkey"; columns: ["state_id","country_id"]; isOneToOne: false; referencedRelation: "states"; referencedColumns: ["id","country_id"] },
        ];
      };
      "service_media": {
        Row: {
          "id": string;
          "service_version_id": string;
          "document_object_id": string;
          "alt_text": string;
          "position": number;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "service_version_id": string;
          "document_object_id": string;
          "alt_text": string;
          "position": number;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "service_version_id"?: string;
          "document_object_id"?: string;
          "alt_text"?: string;
          "position"?: number;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_media_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_media_service_version_id_fkey"; columns: ["service_version_id"]; isOneToOne: false; referencedRelation: "service_versions"; referencedColumns: ["id"] },
        ];
      };
      "service_option_values": {
        Row: {
          "id": string;
          "option_id": string;
          "service_version_id": string;
          "code": string;
          "label": string;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "option_id": string;
          "service_version_id": string;
          "code": string;
          "label": string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "option_id"?: string;
          "service_version_id"?: string;
          "code"?: string;
          "label"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_option_values_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_option_values_option_id_service_version_id_fkey"; columns: ["option_id","service_version_id"]; isOneToOne: false; referencedRelation: "service_options"; referencedColumns: ["id","service_version_id"] },
        ];
      };
      "service_options": {
        Row: {
          "id": string;
          "service_version_id": string;
          "code": string;
          "name": string;
          "required": boolean;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "service_version_id": string;
          "code": string;
          "name": string;
          "required"?: boolean;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "service_version_id"?: string;
          "code"?: string;
          "name"?: string;
          "required"?: boolean;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_options_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_options_service_version_id_fkey"; columns: ["service_version_id"]; isOneToOne: false; referencedRelation: "service_versions"; referencedColumns: ["id"] },
        ];
      };
      "service_requests": {
        Row: {
          "id": string;
          "reference": string;
          "customer_account_id": string;
          "organisation_id": string | null;
          "branch_id": string | null;
          "department_id": string | null;
          "service_id": string;
          "service_version_id": string;
          "booking_schema_id": string;
          "service_location_id": string;
          "status": string;
          "revision": number;
          "preferred_start": string | null;
          "preferred_end": string | null;
          "instructions": string;
          "answers": Json;
          "submitted_at": string | null;
          "reviewed_at": string | null;
          "cancelled_at": string | null;
          "created_at": string;
          "updated_at": string;
          "created_by": string;
        };
        Insert: {
          "id"?: string;
          "reference"?: string;
          "customer_account_id": string;
          "organisation_id"?: string | null;
          "branch_id"?: string | null;
          "department_id"?: string | null;
          "service_id": string;
          "service_version_id": string;
          "booking_schema_id": string;
          "service_location_id": string;
          "status"?: string;
          "revision"?: number;
          "preferred_start"?: string | null;
          "preferred_end"?: string | null;
          "instructions"?: string;
          "answers"?: Json;
          "submitted_at"?: string | null;
          "reviewed_at"?: string | null;
          "cancelled_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by": string;
        };
        Update: {
          "id"?: string;
          "reference"?: string;
          "customer_account_id"?: string;
          "organisation_id"?: string | null;
          "branch_id"?: string | null;
          "department_id"?: string | null;
          "service_id"?: string;
          "service_version_id"?: string;
          "booking_schema_id"?: string;
          "service_location_id"?: string;
          "status"?: string;
          "revision"?: number;
          "preferred_start"?: string | null;
          "preferred_end"?: string | null;
          "instructions"?: string;
          "answers"?: Json;
          "submitted_at"?: string | null;
          "reviewed_at"?: string | null;
          "cancelled_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string;
        };
        Relationships: [
          { foreignKeyName: "service_requests_booking_schema_id_service_version_id_fkey"; columns: ["booking_schema_id","service_version_id"]; isOneToOne: false; referencedRelation: "service_booking_schemas"; referencedColumns: ["id","service_version_id"] },
          { foreignKeyName: "service_requests_branch_id_customer_account_id_organisatio_fkey"; columns: ["branch_id","customer_account_id","organisation_id"]; isOneToOne: false; referencedRelation: "corporate_account_branches"; referencedColumns: ["id","customer_account_id","organisation_id"] },
          { foreignKeyName: "service_requests_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_requests_customer_account_id_fkey"; columns: ["customer_account_id"]; isOneToOne: false; referencedRelation: "customer_profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_requests_organisation_id_fkey"; columns: ["organisation_id"]; isOneToOne: false; referencedRelation: "organisations"; referencedColumns: ["id"] },
          { foreignKeyName: "service_requests_service_location_id_customer_account_id_fkey"; columns: ["service_location_id","customer_account_id"]; isOneToOne: false; referencedRelation: "service_locations"; referencedColumns: ["id","customer_account_id"] },
          { foreignKeyName: "service_requests_service_version_id_service_id_fkey"; columns: ["service_version_id","service_id"]; isOneToOne: false; referencedRelation: "service_versions"; referencedColumns: ["id","service_id"] },
        ];
      };
      "service_requirements": {
        Row: {
          "id": string;
          "service_version_id": string;
          "code": string;
          "description": string;
          "required": boolean;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "service_version_id": string;
          "code": string;
          "description": string;
          "required"?: boolean;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "service_version_id"?: string;
          "code"?: string;
          "description"?: string;
          "required"?: boolean;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_requirements_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_requirements_service_version_id_fkey"; columns: ["service_version_id"]; isOneToOne: false; referencedRelation: "service_versions"; referencedColumns: ["id"] },
        ];
      };
      "service_variants": {
        Row: {
          "id": string;
          "service_version_id": string;
          "code": string;
          "name": string;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "service_version_id": string;
          "code": string;
          "name": string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "service_version_id"?: string;
          "code"?: string;
          "name"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_variants_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_variants_service_version_id_fkey"; columns: ["service_version_id"]; isOneToOne: false; referencedRelation: "service_versions"; referencedColumns: ["id"] },
        ];
      };
      "service_versions": {
        Row: {
          "id": string;
          "service_id": string;
          "version": number;
          "description": string;
          "status": string;
          "assessment_required": boolean;
          "payment_gate": string;
          "published_at": string | null;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
          "pricing_mode": string;
        };
        Insert: {
          "id"?: string;
          "service_id": string;
          "version": number;
          "description": string;
          "status"?: string;
          "assessment_required"?: boolean;
          "payment_gate"?: string;
          "published_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
          "pricing_mode"?: string;
        };
        Update: {
          "id"?: string;
          "service_id"?: string;
          "version"?: number;
          "description"?: string;
          "status"?: string;
          "assessment_required"?: boolean;
          "payment_gate"?: string;
          "published_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
          "pricing_mode"?: string;
        };
        Relationships: [
          { foreignKeyName: "service_versions_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_versions_service_id_fkey"; columns: ["service_id"]; isOneToOne: false; referencedRelation: "services"; referencedColumns: ["id"] },
        ];
      };
      "service_zones": {
        Row: {
          "id": string;
          "state_id": string;
          "code": string;
          "name": string;
          "timezone": string;
          "status": string;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "state_id": string;
          "code": string;
          "name": string;
          "timezone"?: string;
          "status"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "state_id"?: string;
          "code"?: string;
          "name"?: string;
          "timezone"?: string;
          "status"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "service_zones_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "service_zones_state_id_fkey"; columns: ["state_id"]; isOneToOne: false; referencedRelation: "states"; referencedColumns: ["id"] },
        ];
      };
      "services": {
        Row: {
          "id": string;
          "service_family_id": string;
          "code": string;
          "name": string;
          "slug": string;
          "status": string;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "service_family_id": string;
          "code": string;
          "name": string;
          "slug": string;
          "status"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "service_family_id"?: string;
          "code"?: string;
          "name"?: string;
          "slug"?: string;
          "status"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "services_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "services_service_family_id_fkey"; columns: ["service_family_id"]; isOneToOne: false; referencedRelation: "service_families"; referencedColumns: ["id"] },
        ];
      };
      "states": {
        Row: {
          "id": string;
          "country_id": string;
          "code": string;
          "name": string;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
          "status": string;
        };
        Insert: {
          "id"?: string;
          "country_id": string;
          "code": string;
          "name": string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
          "status"?: string;
        };
        Update: {
          "id"?: string;
          "country_id"?: string;
          "code"?: string;
          "name"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
          "status"?: string;
        };
        Relationships: [
          { foreignKeyName: "states_country_id_fkey"; columns: ["country_id"]; isOneToOne: false; referencedRelation: "countries"; referencedColumns: ["id"] },
          { foreignKeyName: "states_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
        ];
      };
      "support_messages": {
        Row: {
          "id": string;
          "ticket_id": string;
          "customer_account_id": string;
          "visibility": string;
          "body": string;
          "created_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "ticket_id": string;
          "customer_account_id": string;
          "visibility"?: string;
          "body": string;
          "created_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "ticket_id"?: string;
          "customer_account_id"?: string;
          "visibility"?: string;
          "body"?: string;
          "created_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "support_messages_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "support_messages_ticket_id_customer_account_id_fkey"; columns: ["ticket_id","customer_account_id"]; isOneToOne: false; referencedRelation: "support_tickets"; referencedColumns: ["id","customer_account_id"] },
        ];
      };
      "support_tickets": {
        Row: {
          "id": string;
          "customer_account_id": string;
          "subject": string;
          "status": string;
          "closed_at": string | null;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "customer_account_id": string;
          "subject": string;
          "status"?: string;
          "closed_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "customer_account_id"?: string;
          "subject"?: string;
          "status"?: string;
          "closed_at"?: string | null;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "support_tickets_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "support_tickets_customer_account_id_fkey"; columns: ["customer_account_id"]; isOneToOne: false; referencedRelation: "customer_profiles"; referencedColumns: ["id"] },
        ];
      };
      "user_preferences": {
        Row: {
          "id": string;
          "profile_id": string;
          "timezone": string;
          "locale": string;
          "created_at": string;
          "updated_at": string;
          "created_by": string | null;
        };
        Insert: {
          "id"?: string;
          "profile_id": string;
          "timezone"?: string;
          "locale"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Update: {
          "id"?: string;
          "profile_id"?: string;
          "timezone"?: string;
          "locale"?: string;
          "created_at"?: string;
          "updated_at"?: string;
          "created_by"?: string | null;
        };
        Relationships: [
          { foreignKeyName: "user_preferences_created_by_fkey"; columns: ["created_by"]; isOneToOne: false; referencedRelation: "profiles"; referencedColumns: ["id"] },
          { foreignKeyName: "user_preferences_profile_id_fkey"; columns: ["profile_id"]; isOneToOne: true; referencedRelation: "profiles"; referencedColumns: ["id"] },
        ];
      };
    };
    Views: { [_ in never]: never };
    Functions: {
      "add_customer_address": { Args: { "p_account_id": string; "p_label": string; "p_address": string; "p_country_id": string; "p_state_id": string; "p_city_id"?: string; }; Returns: string };
      "apply_provider": { Args: { "p_data": Json; "p_key": string; }; Returns: string };
      "approve_pricing_card": { Args: { "p_id": string; }; Returns: string };
      "assessment_command": { Args: { "p_request": string; "p_action": string; "p_data": Json; }; Returns: string };
      "attach_request_document": { Args: { "p_id": string; "p_document": string; }; Returns: string };
      "change_service_request": { Args: { "p_id": string; "p_revision": number; "p_action": string; "p_answers"?: Json; "p_start"?: string; "p_end"?: string; "p_instructions"?: string; }; Returns: number };
      "commercial_policy": { Args: { "p_action": string; "p_data": Json; }; Returns: string };
      "create_pricing_card": { Args: { "p_config": Json; "p_rules": Json; }; Returns: string };
      "create_service_order": { Args: { "p_quote": string; "p_data": Json; "p_key": string; }; Returns: string };
      "create_service_request": { Args: { "p_account": string; "p_version": string; "p_address": string; "p_answers": Json; "p_key": string; "p_branch"?: string; "p_department"?: string; "p_start"?: string; "p_end"?: string; "p_instructions"?: string; }; Returns: string };
      "decide_quotation": { Args: { "p_id": string; "p_action": string; }; Returns: string };
      "discover_order_candidates": { Args: { "p_order": string; "p_unit": string; "p_units": string; "p_after_provider"?: string; "p_after_worker"?: string; "p_limit"?: number; }; Returns: Json };
      "dispatch_command": { Args: { "p_order": string; "p_action": string; "p_data": Json; "p_key": string; }; Returns: string };
      "ensure_individual_customer": { Args: Record<PropertyKey, never>; Returns: string };
      "expire_dispatch_offers": { Args: { "p_limit": number; }; Returns: number };
      "generate_quotation": { Args: { "p_request": string; "p_input": Json; "p_key": string; }; Returns: string };
      "list_order_operations": { Args: { "p_view": string; "p_after"?: string; "p_limit"?: number; }; Returns: Json };
      "list_providers": { Args: { "p_status"?: string; "p_after"?: string; "p_limit"?: number; }; Returns: Json };
      "match_order": { Args: { "p_order": string; "p_candidates": Json; }; Returns: Json };
      "operational_event_worker": { Args: { "p_action": string; "p_data": Json; }; Returns: Json };
      "order_command": { Args: { "p_order": string; "p_action": string; "p_data": Json; "p_key": string; }; Returns: string };
      "order_policy_command": { Args: { "p_action": string; "p_data": Json; "p_key": string; }; Returns: string };
      "personnel_command": { Args: { "p_action": string; "p_data": Json; "p_key": string; }; Returns: string };
      "prepare_customer_upload": { Args: { "p_account_id": string; "p_content_type": string; "p_byte_size": number; }; Returns: Json };
      "prepare_quotation": { Args: { "p_request": string; "p_currency": string; "p_valid_until": string; "p_terms": string; "p_lines": Json; "p_key": string; }; Returns: string };
      "provider_activity": { Args: { "p_provider": string; "p_before"?: string; "p_before_id"?: string; "p_limit"?: number; }; Returns: Json };
      "provider_command": { Args: { "p_provider": string; "p_action": string; "p_data": Json; "p_key": string; }; Returns: string };
      "provider_configuration": { Args: { "p_action": string; "p_data": Json; "p_key": string; }; Returns: string };
      "provider_document_reference": { Args: { "p_provider": string; "p_document": string; }; Returns: Json };
      "provider_eligibility": { Args: { "p_provider": string; "p_service": string; "p_zone": string; "p_start": string; "p_end": string; "p_units": string; "p_worker"?: string; }; Returns: Json };
      "provider_reservation": { Args: { "p_provider": string; "p_action": string; "p_data": Json; "p_key": string; }; Returns: string };
      "read_assessment": { Args: { "p_id": string; }; Returns: Json };
      "read_order": { Args: { "p_order": string; }; Returns: Json };
      "read_order_policy": { Args: { "p_id": string; }; Returns: Json };
      "read_personnel_resource": { Args: { "p_profile": string; }; Returns: Json };
      "read_pricing_card": { Args: { "p_id": string; }; Returns: Json };
      "read_provider": { Args: { "p_provider": string; }; Returns: Json };
      "read_provider_configuration": { Args: { "p_kind": string; "p_id": string; }; Returns: Json };
      "read_quotation": { Args: { "p_id": string; }; Returns: Json };
      "read_quotation_commercial": { Args: { "p_id": string; }; Returns: Json };
      "retire_pricing_card": { Args: { "p_id": string; "p_reason": string; "p_key": string; }; Returns: string };
      "review_service_request": { Args: { "p_id": string; "p_revision": number; }; Returns: number };
    };
    Enums: { [_ in never]: never };
    CompositeTypes: { [_ in never]: never };
  };
};
export type PublicTableName = keyof Database["public"]["Tables"];
export type TableRow<T extends PublicTableName> = Database["public"]["Tables"][T]["Row"];
