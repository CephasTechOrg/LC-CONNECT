'use client';

import { createClient } from '@/lib/supabase/client';

export async function getAccessToken(): Promise<string | null> {
  const supabase = createClient();
  const { data } = await supabase.auth.getSession();
  return data.session?.access_token ?? null;
}

export async function signOut() {
  const supabase = createClient();
  await supabase.auth.signOut();
}
