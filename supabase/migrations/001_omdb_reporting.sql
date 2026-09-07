-- Vestigo: OMDb usage reporting table
-- The iOS app upserts a row for each calendar day so the dashboard can show
-- precise daily/total counts instead of estimating from PostHog events.
--
-- Apply with:  supabase db push
-- Or paste directly into the Supabase SQL editor.

CREATE TABLE IF NOT EXISTS omdb_usage_reports (
  id           BIGSERIAL PRIMARY KEY,
  report_date  DATE        NOT NULL,
  daily_count  INTEGER     NOT NULL DEFAULT 0,
  total_count  INTEGER     NOT NULL DEFAULT 0,
  daily_limit  INTEGER     NOT NULL DEFAULT 1000,
  reported_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (report_date)
);

-- Index for the dashboard query (latest row)
CREATE INDEX IF NOT EXISTS omdb_usage_reports_date_idx ON omdb_usage_reports (report_date DESC);

-- RLS: anonymous clients (the iOS app using the anon key) may only insert/upsert.
-- The dashboard uses the service-role key so it bypasses RLS entirely.
ALTER TABLE omdb_usage_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anon_insert_omdb_usage"
  ON omdb_usage_reports
  FOR INSERT
  TO anon
  WITH CHECK (true);

-- Allow anon UPDATE so the upsert (ON CONFLICT … DO UPDATE) works.
CREATE POLICY "anon_update_omdb_usage"
  ON omdb_usage_reports
  FOR UPDATE
  TO anon
  USING (true)
  WITH CHECK (true);
