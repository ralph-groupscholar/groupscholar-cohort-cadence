# Group Scholar Cohort Cadence

Local-first CLI for managing cohort touchpoints and generating weekly cadence summaries.

## Quickstart

```bash
bin/cohort-cadence init
bin/cohort-cadence add-cohort --name "Spring Fellows" --start-date 2026-03-01 --end-date 2026-06-30 --size 24 --notes "STEM-focused cohort"
bin/cohort-cadence add-touchpoint --cohort "Spring Fellows" --title "Kickoff" --date 2026-03-05 --owner "Program Lead" --channel "Zoom" --notes "Orientation + expectations"
bin/cohort-cadence summary --days 30
bin/cohort-cadence export-ics --days 90 --output data/cadence.ics
bin/cohort-cadence owner-load --days 30
bin/cohort-cadence owner-balance --days 30 --threshold 0.25
bin/cohort-cadence channel-report --lookback 30 --lookahead 30
bin/cohort-cadence status --stale-days 21 --lookahead 30
bin/cohort-cadence cohort-report --cohort "Spring Fellows" --lookback 45 --lookahead 30
bin/cohort-cadence gap-report --lookback 30 --lookahead 30 --status at-risk
bin/cohort-cadence weekly-agenda --weeks 8
bin/cohort-cadence coverage-report --weeks 8
bin/cohort-cadence owner-capacity --weeks 8 --limit 4
bin/cohort-cadence owner-conflicts --days 30 --limit 2
bin/cohort-cadence cadence-metrics --max-gap 21
bin/cohort-cadence action-plan --target-gap 21 --lookahead 30
bin/cohort-cadence db-summary --stale-days 21 --lookahead 30
bin/cohort-cadence seed-db
```

## Data

Data is stored in `data/cadence.json` and can be versioned or shared as needed.

## Cadence Status Checks

Generate a snapshot that flags cohorts with long gaps between touchpoints:

```bash
bin/cohort-cadence status --stale-days 21 --lookahead 30
```

`--stale-days` controls when a cohort is flagged as stale. `--lookahead` shows whether
the next scheduled touchpoint is within the forward window.

## Cadence Gap Report

Surface cohorts without recent touchpoints (lookback) or upcoming ones (lookahead):

```bash
bin/cohort-cadence gap-report --lookback 30 --lookahead 30
```

`--lookback` flags cohorts missing recent touchpoints. `--lookahead` flags cohorts
that have no upcoming touchpoints scheduled.

You can optionally filter by status (`at-risk`, `stale`, `unscheduled`, `on-track`):

```bash
bin/cohort-cadence gap-report --lookback 45 --lookahead 21 --status stale
```

## Cohort Report

Generate a touchpoint timeline for a specific cohort:

```bash
bin/cohort-cadence cohort-report --cohort "Spring Fellows" --lookback 45 --lookahead 30
```

`--lookback` controls how far back the recent list runs. `--lookahead` controls the upcoming window.

## Cadence Metrics

Summarize average and maximum gaps between touchpoints per cohort:

```bash
bin/cohort-cadence cadence-metrics --max-gap 30
```

Use `--max-gap` to flag cohorts with gaps larger than the threshold. Omit the flag to run the report without highlighting.

## Owner Load Report

Summarize upcoming touchpoints grouped by owner:

```bash
bin/cohort-cadence owner-load --days 30
```

Filter to a specific owner:

```bash
bin/cohort-cadence owner-load --days 45 --owner "Program Lead"
```

## Owner Balance

Quantify workload balance across owners in the upcoming window:

```bash
bin/cohort-cadence owner-balance --days 30 --threshold 0.25
```

`--threshold` sets the relative imbalance tolerance (25% default). Owners beyond the
threshold are flagged as `overloaded` or `underloaded`.

## Channel Report

Review touchpoints grouped by channel within a combined lookback/lookahead window:

```bash
bin/cohort-cadence channel-report --lookback 30 --lookahead 30
```

Filter by owner or cohort:

```bash
bin/cohort-cadence channel-report --lookback 45 --lookahead 21 --owner "Program Lead"
bin/cohort-cadence channel-report --lookback 45 --lookahead 21 --cohort "Spring Fellows"
```

## Calendar Export

Export upcoming touchpoints to an iCalendar file for import into calendar tools:

```bash
bin/cohort-cadence export-ics --days 90 --output data/cadence.ics
```

## Weekly Agenda

Generate a week-by-week agenda of upcoming touchpoints:

```bash
bin/cohort-cadence weekly-agenda --weeks 8
```

Filter to a specific owner or cohort:

```bash
bin/cohort-cadence weekly-agenda --weeks 6 --owner "Program Lead"
bin/cohort-cadence weekly-agenda --weeks 6 --cohort "Spring Fellows"
```

## Coverage Report

Review weekly coverage for each cohort to spot empty weeks in the upcoming window:

```bash
bin/cohort-cadence coverage-report --weeks 8
```

Filter to a specific cohort:

```bash
bin/cohort-cadence coverage-report --weeks 6 --cohort "Spring Fellows"
```

## Owner Capacity

Review weekly touchpoint load by owner and flag overloaded weeks:

```bash
bin/cohort-cadence owner-capacity --weeks 8 --limit 4
```

The report includes zero-count weeks so you can spot upcoming gaps in owner schedules.

Filter to a single owner:

```bash
bin/cohort-cadence owner-capacity --weeks 6 --limit 3 --owner "Program Lead"
```

## Owner Conflicts

Identify dates where an owner has too many touchpoints scheduled:

```bash
bin/cohort-cadence owner-conflicts --days 30 --limit 2
```

Filter to a single owner:

```bash
bin/cohort-cadence owner-conflicts --days 45 --limit 2 --owner "Program Lead"
```

## Action Plan

Generate a recommended next-touchpoint plan for cohorts that need cadence attention:

```bash
bin/cohort-cadence action-plan --target-gap 21 --lookahead 30
```

`--target-gap` sets the desired maximum gap between touchpoints. `--lookahead`
controls the window used to flag whether the recommended next touchpoint is soon.

## Database Sync (Optional)

To push local cadence data into the Group Scholar Postgres database, set
`GS_CADENCE_DATABASE_URL` (or `DATABASE_URL`) in the environment and run:

```bash
bin/cohort-cadence sync-db
```

This will create a dedicated schema (`groupscholar_cohort_cadence`) and upsert
cohorts/touchpoints plus a sync event log. Install the dependency with
`gem install pg` before syncing.

## Database Summary (Optional)

Pull a read-only digest from Postgres with upcoming touchpoints and stale cohorts:

```bash
bin/cohort-cadence db-summary --stale-days 21 --lookahead 30
```

This uses the same database URL environment variables as `sync-db`.

## Database Seed (Optional)

Seed the production database with realistic sample cohorts and touchpoints:

```bash
bin/cohort-cadence seed-db
```

## Testing

Run the CLI store tests:

```bash
ruby -I lib test/test_owner_capacity.rb
ruby -I lib test/test_owner_conflicts.rb
ruby -I lib test/test_channel_report.rb
ruby -I lib test/test_cohort_coverage.rb
```

This uses the same database URL environment variables as `sync-db`.
