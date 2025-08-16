# Group Scholar Cohort Cadence

Local-first CLI for managing cohort touchpoints and generating weekly cadence summaries.

## Quickstart

```bash
bin/cohort-cadence init
bin/cohort-cadence add-cohort --name "Spring Fellows" --start-date 2026-03-01 --end-date 2026-06-30 --size 24 --notes "STEM-focused cohort"
bin/cohort-cadence add-touchpoint --cohort "Spring Fellows" --title "Kickoff" --date 2026-03-05 --owner "Program Lead" --channel "Zoom" --notes "Orientation + expectations"
bin/cohort-cadence summary --days 30
bin/cohort-cadence status --stale-days 21 --lookahead 30
bin/cohort-cadence gap-report --lookback 30 --lookahead 30
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

## Database Sync (Optional)

To push local cadence data into the Group Scholar Postgres database, set
`GS_CADENCE_DATABASE_URL` (or `DATABASE_URL`) in the environment and run:

```bash
bin/cohort-cadence sync-db
```

This will create a dedicated schema (`groupscholar_cohort_cadence`) and upsert
cohorts/touchpoints plus a sync event log. Install the dependency with
`gem install pg` before syncing.
