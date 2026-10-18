"use client";

import { useState } from "react";

export default function SupabaseConnectionTest() {
  const [status, setStatus] = useState("Click the button to check your connection.");
  const [checking, setChecking] = useState(false);
  const [connected, setConnected] = useState<boolean | null>(null);

  async function testConnection() {
    setChecking(true);
    setConnected(null);
    setStatus("Checking Supabase…");

    try {
      const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
      if (!url || !key) {
        throw new Error("Add your Supabase URL and anon key to .env.local, then restart the development server.");
      }

      const response = await fetch(`${url.replace(/\/$/, "")}/auth/v1/settings`, {
        headers: { apikey: key },
        cache: "no-store",
        signal: AbortSignal.timeout(15000),
      });

      if (!response.ok) {
        throw new Error(`Supabase returned HTTP ${response.status}. Check your project URL and anon key.`);
      }

      setConnected(true);
      setStatus("Connected to Supabase! Your app successfully reached the Auth service.");
    } catch (error) {
      setConnected(false);
      setStatus(
        error instanceof Error && error.message.startsWith("Supabase returned")
          ? error.message
          : "Connection failed. Check your internet connection, Supabase URL and anon key, then try again.",
      );
    } finally {
      setChecking(false);
    }
  }

  return (
    <section aria-label="Supabase connection" className="w-full max-w-md rounded-xl border border-zinc-300 p-5 text-left dark:border-zinc-700">
      <h2 className="text-lg font-semibold text-black dark:text-zinc-50">Supabase connection</h2>
      <button
        type="button"
        onClick={testConnection}
        disabled={checking}
        className="mt-4 rounded-lg bg-blue-700 px-4 py-2 font-medium text-white hover:bg-blue-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-500 disabled:cursor-wait disabled:opacity-60"
      >
        {checking ? "Checking…" : "Test Supabase connection"}
      </button>
      <p role="status" aria-live="polite" className={`mt-3 text-sm ${connected === true ? "text-green-700 dark:text-green-400" : connected === false ? "text-red-700 dark:text-red-400" : "text-zinc-600 dark:text-zinc-400"}`}>
        {status}
      </p>
      <p className="mt-2 text-xs text-zinc-500 dark:text-zinc-400">This checks connectivity. Database table permissions require a separate test.</p>
    </section>
  );
}
