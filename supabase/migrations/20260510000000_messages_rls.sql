-- Migration: Messages Table Row Level Security
-- Created:    2026-05-10
-- Purpose:    Protect the messages table so only match participants can read
--             their own messages, and all direct client-side inserts are blocked.
--
-- When to rerun this file:
--   1. First-time setup of a new Supabase project
--   2. After a full Supabase project reset (Project Settings → Danger Zone → Reset)
--   3. When creating a new environment (e.g. staging alongside production)
--   4. If the messages table is accidentally dropped and recreated
--
-- Safe to run multiple times — all statements use IF EXISTS / IF NOT EXISTS.
-- ============================================================================


-- Step 1: Enable RLS on the messages table
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;


-- Step 2: Remove any Supabase auto-generated open-read policy if it exists.
-- Supabase Dashboard's Table Editor sometimes auto-creates a permissive anon
-- read policy when a table is first created through the UI. This policy would
-- override all other SELECT policies (PostgreSQL ORs them together) and expose
-- all messages to anyone with the anon key. We drop it defensively here.
DROP POLICY IF EXISTS "anon_can_read_messages" ON messages;


-- Step 3: Allow users to read only messages from matches they belong to.
-- auth.uid() resolves to the user's UUID from the JWT passed by the client.
-- This works because the FastAPI JWT includes sub (user UUID) and
-- role: authenticated, and the Supabase JWT Secret matches the backend
-- JWT_SECRET_KEY, allowing Supabase to verify and decode the token.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'messages'
    AND policyname = 'participants can read their messages'
  ) THEN
    CREATE POLICY "participants can read their messages"
    ON messages FOR SELECT
    USING (
      EXISTS (
        SELECT 1 FROM matches
        WHERE matches.id = messages.match_id
          AND (matches.user_a_id = auth.uid() OR matches.user_b_id = auth.uid())
      )
    );
  END IF;
END $$;


-- Step 4: Block all direct inserts via client keys (anon or user JWT).
-- All message writes go through FastAPI using the service_role key,
-- which bypasses RLS entirely. No legitimate client should ever insert
-- directly into this table.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'messages'
    AND policyname = 'no direct inserts'
  ) THEN
    CREATE POLICY "no direct inserts"
    ON messages FOR INSERT
    WITH CHECK (false);
  END IF;
END $$;


-- ============================================================================
-- Verification — run these after applying to confirm everything is correct:
--
-- SELECT relname, relrowsecurity FROM pg_class WHERE relname = 'messages';
-- → relrowsecurity should be: true
--
-- SELECT policyname, cmd FROM pg_policies WHERE tablename = 'messages';
-- → should show exactly two rows:
--     participants can read their messages  |  SELECT
--     no direct inserts                     |  INSERT
--
-- SELECT rolname, rolbypassrls FROM pg_roles WHERE rolname = 'anon';
-- → rolbypassrls should be: false
-- ============================================================================
