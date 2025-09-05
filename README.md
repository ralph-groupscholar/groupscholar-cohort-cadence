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
bin/cohort-cadence status --stale-days 21 --lookahead 30
bin/cohort-cadence cohort-report --cohort "Spring Fellows" --lookback 45 --lookahead 30
bin/cohort-cadence gap-report --lookback 30 --lookahead 30 --status at-risk
bin/cohort-cadence db-summary --stale-days 21 --lookahead 30
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

## Owner Load Report

Summarize upcoming touchpoints grouped by owner:

```bash
bin/cohort-cadence owner-load --days 30
```

Filter to a specific owner:

```bash
bin/cohort-cadence owner-load --days 45 --owner "Program Lead"
```

## Calendar Export

Export upcoming touchpoints to an iCalendar file for import into calendar tools:

```bash
bin/cohort-cadence export-ics --days 90 --output data/cadence.ics
```

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
