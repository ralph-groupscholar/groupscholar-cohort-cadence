# frozen_string_literal: true

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

    def upsert_cohorts(conn, cohorts)
      cohorts.each do |cohort|
        conn.exec_params(<<~SQL, [
          cohort["id"],
          cohort["name"],
          cohort["start_date"],
          cohort["end_date"],
          cohort["size"].to_i,
          cohort["notes"],
          cohort["created_at"]
        ])
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
      end
    end

    def upsert_touchpoints(conn, touchpoints)
      touchpoints.each do |touch|
        conn.exec_params(<<~SQL, [
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
      end
    end

    def log_sync(conn, data)
      conn.exec_params(
        "INSERT INTO #{SCHEMA}.sync_events (synced_at, cohorts_count, touchpoints_count) VALUES ($1, $2, $3)",
        [Time.now.utc.iso8601, data.fetch("cohorts", []).size, data.fetch("touchpoints", []).size]
      )
    end
  end
end
