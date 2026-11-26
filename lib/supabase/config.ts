const placeholder = /^(your-|replace-with-|changeme|example$)/i;

export function getSupabaseConfig() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (!url || !key || placeholder.test(url) || placeholder.test(key)) return null;

  try {
    const parsed = new URL(url);
    return (parsed.protocol === "https:" || parsed.protocol === "http:") && parsed.hostname
      ? { url, key }
      : null;
  } catch {
    return null;
  }
}

export function isSupabaseConfigured() {
  return getSupabaseConfig() !== null;
}
