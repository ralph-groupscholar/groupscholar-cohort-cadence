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

## Iteration 62
- Added cohort-report command to generate per-cohort touchpoint timelines.
- Implemented cohort report aggregation with lookback/lookahead windows and last/next stats.
- Documented the new cohort report workflow in the README.

## Iteration 69
- Added an export-ics command to generate iCalendar files for upcoming touchpoints.
- Implemented iCalendar rendering with proper escaping and all-day event formatting.
- Documented calendar export usage in the README.

## Iteration 102
- Added a weekly-agenda command to group upcoming touchpoints by week with optional owner/cohort filters.
- Implemented weekly agenda aggregation in the store with week windows and filter handling.
- Documented weekly agenda usage in the README.

## Iteration 97
- Added cadence metrics reporting to summarize touchpoint gap statistics per cohort.
- Implemented gap threshold flagging with average/min/max gap calculations.
- Documented the cadence metrics command in the README and CLI usage.

## Iteration 70
- Added Postgres seed workflow with realistic cohort/touchpoint sample data.
- Added seed-db CLI command and documented database seeding in the README.
- Seeded the production Postgres schema with starter cadence data.

## Iteration 34
- Added action-plan CLI command to recommend next touchpoints based on target gap and lookahead windows.
- Implemented action plan rendering in the CLI output with recommended owners and dates.
- Added action plan tests plus README updates documenting the new workflow.

## Iteration 36
- Added channel-report command to summarize touchpoints by channel with lookback/lookahead windows and filters.
- Implemented channel report aggregation in the store with owner/cohort rollups and last/next touchpoint stats.
- Added channel report rendering, CLI usage docs, and new store tests.

## Iteration 35
- Added owner-conflicts report to flag days when owners exceed daily touchpoint limits.
- Implemented conflict aggregation logic in the cadence store and CLI rendering.
- Documented the new report in the README and added tests.

## Iteration 103
- Added owner balance reporting to flag under/overloaded owners in upcoming windows.
- Implemented CLI rendering and usage docs for owner-balance with imbalance thresholds.
- Added owner balance tests to validate workload status classification.

## Iteration 38
- Added cohort coverage reporting to flag empty upcoming weeks and coverage rates.
- Implemented coverage-report CLI command and rendering with weekly counts.
- Added coverage report tests and documented the workflow in the README.

## Iteration 133
- Added weekday-report command to summarize touchpoints by weekday with owner/cohort filters.
- Implemented weekday report aggregation in the store and CLI rendering output.
- Documented weekday report usage in the README and added tests.

## Iteration 104
- Expanded owner capacity reporting to include zero-count weeks within the window.
- Adjusted owner capacity tests and docs to reflect the fuller weekly coverage view.
