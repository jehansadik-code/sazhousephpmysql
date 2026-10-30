# MySQL migrations

`../schema.mysql.sql` is the complete schema for a fresh empty database. Do not run it against a database that already contains SAZ House data.

Apply numbered migration files in ascending order to an existing PHP/MySQL installation after taking and verifying a database backup. Record each successfully applied filename in the deployment record. Each migration is additive or data-preserving. Migrations `003_store_state_revisions.sql` and `004_seed_required_store_state.sql` are replay-safe on MySQL 8.0.46: `003` checks `information_schema.columns` before preparing its additive `ALTER`, and `004` inserts only missing state records. The other migrations must still be treated as one-time upgrades unless their own SQL says otherwise. Read the comments in a migration before applying it; some optional indexes require a duplicate-data audit first.
