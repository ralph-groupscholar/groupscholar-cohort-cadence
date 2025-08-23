# Group Scholar Cohort Cadence Progress

## Iteration 1
- Bootstrapped the Ruby CLI project structure with data storage.
- Implemented commands for cohort intake, touchpoint logging, upcoming views, and summary generation.
- Added a quickstart README to document usage and storage format.

## Iteration 2
- Added optional Postgres sync command with schema/table bootstrap and upserts.
- Documented database sync usage and dependency requirements in the README.

## Iteration 3
- Added cadence gap report logic to surface cohorts missing recent or upcoming touchpoints.
- Extended the CLI and README with the new gap-report command and usage notes.

## Iteration 2
- Added Postgres sync implementation with schema/table creation, upserts, and sync event logging.
- Wired optional database sync to use GS_CADENCE_DATABASE_URL or DATABASE_URL safely.

## Iteration 3
- Added cadence status reporting with stale cadence detection and lookahead flags.
- Documented the new status command in the README.

## Iteration 17
- Added status filtering to the cadence gap report output and CLI usage.
- Expanded gap report rendering to handle empty filters gracefully.
- Documented gap report status filters in the README.
- Added validation for gap report status filters to prevent typos.

## Iteration 61
- Added owner load reporting to summarize upcoming touchpoints grouped by owner.
- Extended CLI and README with owner-load usage and optional owner filtering.

## Iteration 68
- Added a db-summary command that reads Postgres for upcoming touchpoints and stale cohort signals.
- Implemented database summary queries with last-sync metadata and active stale cohort detection.
- Documented the new database summary workflow in the README.

## Iteration 69
- Added an export-ics command to generate iCalendar files for upcoming touchpoints.
- Implemented iCalendar rendering with proper escaping and all-day event formatting.
- Documented calendar export usage in the README.
