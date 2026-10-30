-- The original contact_messages.id column was PostgreSQL text rather than UUID.
-- This non-destructive widening preserves every historical message identifier.
ALTER TABLE contact_messages MODIFY id VARCHAR(100) NOT NULL;
