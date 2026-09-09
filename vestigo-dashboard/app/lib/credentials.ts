import { createClient } from '@supabase/supabase-js'

export interface StoredCredential {
  credential_id: string  // base64url
  public_key: string     // base64url
  counter: number
}

function db() {
  return createClient(process.env.SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!)
}

export async function listCredentials(): Promise<StoredCredential[]> {
  const { data } = await db()
    .from('dashboard_credentials')
    .select('credential_id, public_key, counter')
  return (data ?? []) as StoredCredential[]
}

export async function saveCredential(cred: StoredCredential): Promise<void> {
  await db().from('dashboard_credentials').insert(cred)
}

export async function updateCounter(credentialId: string, counter: number): Promise<void> {
  await db()
    .from('dashboard_credentials')
    .update({ counter })
    .eq('credential_id', credentialId)
}

export async function findCredential(credentialId: string): Promise<StoredCredential | null> {
  const { data } = await db()
    .from('dashboard_credentials')
    .select('credential_id, public_key, counter')
    .eq('credential_id', credentialId)
    .single()
  return data as StoredCredential | null
}
