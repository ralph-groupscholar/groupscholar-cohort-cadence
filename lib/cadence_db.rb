# frozen_string_literal: true

require "date"
require "time"
require "pg"

module GroupScholar
  class CadenceDB
    SCHEMA = "groupscholar_cohort_cadence"

    def initialize(url: nil)
      @url = url || ENV["GS_CADENCE_DATABASE_URL"] || ENV["DATABASE_URL"]
      raise "Missing GS_CADENCE_DATABASE_URL (or DATABASE_URL) for Postgres sync." if @url.nil? || @url.strip.empty?
    end

    def sync!(data)
      conn = PG::Connection.new(@url)
      ensure_schema(conn)
      conn.exec("BEGIN")
      upsert_cohorts(conn, data.fetch("cohorts", []))
      upsert_touchpoints(conn, data.fetch("touchpoints", []))
      log_sync(conn, data)
      conn.exec("COMMIT")
    rescue StandardError => e
      conn.exec("ROLLBACK") if conn
      raise e
    ensure
      conn&.close
    end

    def summary(lookahead_days, stale_days)
      conn = PG::Connection.new(@url)
      ensure_schema(conn)
      {
        "generated_at" => Time.now.utc.iso8601,
        "cohort_count" => fetch_count(conn, "cohorts"),
        "touchpoint_count" => fetch_count(conn, "touchpoints"),
        "last_sync" => fetch_last_sync(conn),
        "upcoming" => fetch_upcoming(conn, lookahead_days),
        "stale_cohorts" => fetch_stale_cohorts(conn, stale_days)
      }
    ensure
      conn&.close
    end

    def seed!
      conn = PG::Connection.new(@url)
      ensure_schema(conn)
      data = seed_data
      conn.exec("BEGIN")
      upsert_cohorts(conn, data.fetch("cohorts", []))
      upsert_touchpoints(conn, data.fetch("touchpoints", []))
      log_sync(conn, data)
      conn.exec("COMMIT")
      {
        "cohorts" => data.fetch("cohorts", []).size,
        "touchpoints" => data.fetch("touchpoints", []).size
      }
    rescue StandardError => e
      conn.exec("ROLLBACK") if conn
      raise e
    ensure
      conn&.close
    end

    private

    def ensure_schema(conn)
      conn.exec("CREATE SCHEMA IF NOT EXISTS #{SCHEMA}")
      conn.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS #{SCHEMA}.cohorts (
          id text PRIMARY KEY,
          name text NOT NULL,
          start_date date NOT NULL,
          end_date date NOT NULL,
          size integer NOT NULL,
          notes text,
          created_at timestamptz NOT NULL
        );
      SQL
      conn.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS #{SCHEMA}.touchpoints (
          id text PRIMARY KEY,
          cohort_id text NOT NULL,
          cohort_name text NOT NULL,
          title text NOT NULL,
          date date NOT NULL,
          owner text NOT NULL,
          channel text NOT NULL,
          notes text,
          created_at timestamptz NOT NULL
        );
      SQL
      conn.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS #{SCHEMA}.sync_events (
          id bigserial PRIMARY KEY,
          synced_at timestamptz NOT NULL,
          cohorts_count integer NOT NULL,
          touchpoints_count integer NOT NULL
        );
      SQL
      conn.exec("CREATE INDEX IF NOT EXISTS touchpoints_date_idx ON #{SCHEMA}.touchpoints (date)")
    end

    def fetch_count(conn, table)
      conn.exec("SELECT COUNT(*) FROM #{SCHEMA}.#{table}").getvalue(0, 0).to_i
    end

    def fetch_last_sync(conn)
      result = conn.exec(<<~SQL)
        SELECT synced_at, cohorts_count, touchpoints_count
        FROM #{SCHEMA}.sync_events
        ORDER BY synced_at DESC
        LIMIT 1;
      SQL
      return nil if result.ntuples.zero?
      {
        "synced_at" => result.getvalue(0, 0),
        "cohorts_count" => result.getvalue(0, 1).to_i,
        "touchpoints_count" => result.getvalue(0, 2).to_i
      }
    end

    def fetch_upcoming(conn, lookahead_days)
      result = conn.exec_params(<<~SQL, [lookahead_days])
        SELECT id, cohort_id, cohort_name, title, date, owner, channel
        FROM #{SCHEMA}.touchpoints
        WHERE date >= CURRENT_DATE
          AND date <= CURRENT_DATE + $1
        ORDER BY date ASC;
      SQL
      result.map do |row|
        {
          "id" => row["id"],
          "cohort_id" => row["cohort_id"],
          "cohort_name" => row["cohort_name"],
          "title" => row["title"],
          "date" => row["date"],
          "owner" => row["owner"],
          "channel" => row["channel"]
        }
      end
    end

    def fetch_stale_cohorts(conn, stale_days)
      result = conn.exec_params(<<~SQL, [stale_days])
        WITH last_touch AS (
          SELECT cohort_id, MAX(date) AS last_date
          FROM #{SCHEMA}.touchpoints
          WHERE date <= CURRENT_DATE
          GROUP BY cohort_id
        ),
        active_cohorts AS (
          SELECT c.*, lt.last_date,
            (CURRENT_DATE - COALESCE(lt.last_date, c.start_date))::int AS days_since_last
          FROM #{SCHEMA}.cohorts c
          LEFT JOIN last_touch lt ON c.id = lt.cohort_id
          WHERE c.start_date <= CURRENT_DATE AND c.end_date >= CURRENT_DATE
        )
        SELECT id, name, last_date, days_since_last
        FROM active_cohorts
        WHERE days_since_last > $1
        ORDER BY days_since_last DESC
        LIMIT 10;
      SQL
      result.map do |row|
        {
          "id" => row["id"],
          "name" => row["name"],
          "last_touchpoint" => row["last_date"],
          "days_since_last" => row["days_since_last"].to_i
        }
      end
    end

    def upsert_cohorts(conn, cohorts)
      cohorts.each do |cohort|
        sql = <<~SQL
          INSERT INTO #{SCHEMA}.cohorts
            (id, name, start_date, end_date, size, notes, created_at)
          VALUES
            ($1, $2, $3, $4, $5, $6, $7)
          ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            start_date = EXCLUDED.start_date,
            end_date = EXCLUDED.end_date,
            size = EXCLUDED.size,
            notes = EXCLUDED.notes,
            created_at = EXCLUDED.created_at;
        SQL
        conn.exec_params(sql, [
          cohort["id"],
          cohort["name"],
          cohort["start_date"],
          cohort["end_date"],
          cohort["size"].to_i,
          cohort["notes"],
          cohort["created_at"]
        ])
      end
    end

    def upsert_touchpoints(conn, touchpoints)
      touchpoints.each do |touch|
        sql = <<~SQL
          INSERT INTO #{SCHEMA}.touchpoints
            (id, cohort_id, cohort_name, title, date, owner, channel, notes, created_at)
          VALUES
            ($1, $2, $3, $4, $5, $6, $7, $8, $9)
          ON CONFLICT (id) DO UPDATE SET
            cohort_id = EXCLUDED.cohort_id,
            cohort_name = EXCLUDED.cohort_name,
            title = EXCLUDED.title,
            date = EXCLUDED.date,
            owner = EXCLUDED.owner,
            channel = EXCLUDED.channel,
            notes = EXCLUDED.notes,
            created_at = EXCLUDED.created_at;
        SQL
        conn.exec_params(sql, [
          touch["id"],
          touch["cohort_id"],
          touch["cohort_name"],
          touch["title"],
          touch["date"],
          touch["owner"],
          touch["channel"],
          touch["notes"],
          touch["created_at"]
        ])
      end
    end

    def log_sync(conn, data)
      conn.exec_params(
        "INSERT INTO #{SCHEMA}.sync_events (synced_at, cohorts_count, touchpoints_count) VALUES ($1, $2, $3)",
        [Time.now.utc.iso8601, data.fetch("cohorts", []).size, data.fetch("touchpoints", []).size]
      )
    end

    def seed_data
      today = Date.today
      created_at = Time.now.utc.iso8601
      cohorts = [
        {
          "id" => "seed-cohort-spring-2026",
          "name" => "Spring 2026 Fellows",
          "start_date" => (today - 28).iso8601,
          "end_date" => (today + 120).iso8601,
          "size" => 26,
          "notes" => "STEM focus with rural outreach partners.",
          "created_at" => created_at
        },
        {
          "id" => "seed-cohort-summer-2026",
          "name" => "Summer 2026 Explorers",
          "start_date" => (today + 42).iso8601,
          "end_date" => (today + 150).iso8601,
          "size" => 18,
          "notes" => "Bridge cohort preparing for fall internships.",
          "created_at" => created_at
        },
        {
          "id" => "seed-cohort-fall-2025",
          "name" => "Fall 2025 Alumni",
          "start_date" => (today - 210).iso8601,
          "end_date" => (today - 30).iso8601,
          "size" => 22,
          "notes" => "Wrap-up cohort awaiting final outcomes.",
          "created_at" => created_at
        }
      ]

      touchpoints = [
        {
          "id" => "seed-touchpoint-01",
          "cohort_id" => "seed-cohort-spring-2026",
          "cohort_name" => "Spring 2026 Fellows",
          "title" => "Program kickoff and expectations",
          "date" => (today - 21).iso8601,
          "owner" => "Maya Torres",
          "channel" => "Zoom",
          "notes" => "Orientation with scholar success roadmap.",
          "created_at" => created_at
        },
        {
          "id" => "seed-touchpoint-02",
          "cohort_id" => "seed-cohort-spring-2026",
          "cohort_name" => "Spring 2026 Fellows",
          "title" => "Financial aid check-in",
          "date" => (today - 7).iso8601,
          "owner" => "Jordan Lee",
          "channel" => "Email",
          "notes" => "Confirm FAFSA status and next steps.",
          "created_at" => created_at
        },
        {
          "id" => "seed-touchpoint-03",
          "cohort_id" => "seed-cohort-spring-2026",
          "cohort_name" => "Spring 2026 Fellows",
          "title" => "Mid-term momentum pulse",
          "date" => (today + 12).iso8601,
          "owner" => "Maya Torres",
          "channel" => "Phone",
          "notes" => "Collect blockers and support requests.",
          "created_at" => created_at
        },
        {
          "id" => "seed-touchpoint-04",
          "cohort_id" => "seed-cohort-spring-2026",
          "cohort_name" => "Spring 2026 Fellows",
          "title" => "Career readiness workshop",
          "date" => (today + 35).iso8601,
          "owner" => "Priya Shah",
          "channel" => "In-person",
          "notes" => "Resume clinic with employer partners.",
          "created_at" => created_at
        },
        {
          "id" => "seed-touchpoint-05",
          "cohort_id" => "seed-cohort-summer-2026",
          "cohort_name" => "Summer 2026 Explorers",
          "title" => "Pre-launch welcome",
          "date" => (today + 45).iso8601,
          "owner" => "Alex Grant",
          "channel" => "Email",
          "notes" => "Share onboarding checklist and timelines.",
          "created_at" => created_at
        },
        {
          "id" => "seed-touchpoint-06",
          "cohort_id" => "seed-cohort-summer-2026",
          "cohort_name" => "Summer 2026 Explorers",
          "title" => "Mentor match kickoff",
          "date" => (today + 60).iso8601,
          "owner" => "Priya Shah",
          "channel" => "Zoom",
          "notes" => "Introduce mentors and set cadence.",
          "created_at" => created_at
        },
        {
          "id" => "seed-touchpoint-07",
          "cohort_id" => "seed-cohort-fall-2025",
          "cohort_name" => "Fall 2025 Alumni",
          "title" => "Outcome survey reminder",
          "date" => (today - 45).iso8601,
          "owner" => "Jordan Lee",
          "channel" => "SMS",
          "notes" => "Final outcomes capture for reporting.",
          "created_at" => created_at
        },
        {
          "id" => "seed-touchpoint-08",
          "cohort_id" => "seed-cohort-fall-2025",
          "cohort_name" => "Fall 2025 Alumni",
          "title" => "Alumni spotlight follow-up",
          "date" => (today - 20).iso8601,
          "owner" => "Alex Grant",
          "channel" => "Email",
          "notes" => "Capture story highlights for newsletters.",
          "created_at" => created_at
        }
      ]

      {
        "cohorts" => cohorts,
        "touchpoints" => touchpoints
      }
    end
  end
end
