# Group Scholar Cohort Cadence

Local-first CLI for managing cohort touchpoints and generating weekly cadence summaries.

## Quickstart

```bash
bin/cohort-cadence init
bin/cohort-cadence add-cohort --name "Spring Fellows" --start-date 2026-03-01 --end-date 2026-06-30 --size 24 --notes "STEM-focused cohort"
bin/cohort-cadence add-touchpoint --cohort "Spring Fellows" --title "Kickoff" --date 2026-03-05 --owner "Program Lead" --channel "Zoom" --notes "Orientation + expectations"
bin/cohort-cadence summary --days 30
```

## Data

Data is stored in `data/cadence.json` and can be versioned or shared as needed.
