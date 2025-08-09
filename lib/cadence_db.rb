# frozen_string_literal: true

begin
  require "pg"
rescue LoadError
  raise "Missing dependency: pg gem. Install with `gem install pg` to use database sync."
end

module GroupScholar
  class CadenceDB
    DEFAULT_SCHEMA = "groupscholar_cohort_cadence"

    def initialize
      @database_url = ENV["GS_CADENCE_DATABASE_URL"] || ENV["DATABASE_URL"]
      raise "GS_CADENCE_DATABASE_URL is not set." unless @database_url
    end

    def sync!(data)
      with_connection do |conn|
        ensure_schema!(conn)
        upsert_cohorts(conn, data["cohorts"])
        upsert_touchpoints(conn, data["touchpoints"])
        conn.exec_params(
          "INSERT INTO #{schema_table('sync_events')} (synced_at, cohorts, touchpoints) VALUES ($1, $2, $3)",
          [Time.now.utc, data["cohorts"].size, data["touchpoints"].size]
        )
      end
    end

    private

    def with_connection
      conn = PG.connect(@database_url)
      yield conn
    ensure
      conn&.close
    end

    def ensure_schema!(conn)
      conn.exec("CREATE SCHEMA IF NOT EXISTS #{DEFAULT_SCHEMA}")
      conn.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS #{schema_table("cohorts")} (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          start_date DATE NOT NULL,
          end_date DATE NOT NULL,
          size INTEGER NOT NULL,
          notes TEXT NOT NULL,
          created_at TIMESTAMPTZ NOT NULL
        )
      SQL
      conn.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS #{schema_table("touchpoints")} (
          id TEXT PRIMARY KEY,
          cohort_id TEXT NOT NULL REFERENCES #{schema_table("cohorts")}(id),
          cohort_name TEXT NOT NULL,
          title TEXT NOT NULL,
          date DATE NOT NULL,
          owner TEXT NOT NULL,
          channel TEXT NOT NULL,
          notes TEXT NOT NULL,
          created_at TIMESTAMPTZ NOT NULL
        )
      SQL
      conn.exec(<<~SQL)
        CREATE TABLE IF NOT EXISTS #{schema_table("sync_events")} (
          id BIGSERIAL PRIMARY KEY,
          synced_at TIMESTAMPTZ NOT NULL,
          cohorts INTEGER NOT NULL,
          touchpoints INTEGER NOT NULL
        )
      SQL
    end

    def upsert_cohorts(conn, cohorts)
      cohorts.each do |cohort|
        conn.exec_params(
          <<~SQL,
            INSERT INTO #{schema_table("cohorts")} (id, name, start_date, end_date, size, notes, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            ON CONFLICT (id) DO UPDATE SET
              name = EXCLUDED.name,
              start_date = EXCLUDED.start_date,
              end_date = EXCLUDED.end_date,
              size = EXCLUDED.size,
              notes = EXCLUDED.notes,
              created_at = EXCLUDED.created_at
          SQL
          [
            cohort.fetch("id"),
            cohort.fetch("name"),
            Date.parse(cohort.fetch("start_date")),
            Date.parse(cohort.fetch("end_date")),
            cohort.fetch("size").to_i,
            cohort.fetch("notes"),
            DateTime.parse(cohort.fetch("created_at"))
          ]
        )
      end
    end

    def upsert_touchpoints(conn, touchpoints)
      touchpoints.each do |touch|
        conn.exec_params(
          <<~SQL,
            INSERT INTO #{schema_table("touchpoints")} (id, cohort_id, cohort_name, title, date, owner, channel, notes, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            ON CONFLICT (id) DO UPDATE SET
              cohort_id = EXCLUDED.cohort_id,
              cohort_name = EXCLUDED.cohort_name,
              title = EXCLUDED.title,
              date = EXCLUDED.date,
              owner = EXCLUDED.owner,
              channel = EXCLUDED.channel,
              notes = EXCLUDED.notes,
              created_at = EXCLUDED.created_at
          SQL
          [
            touch.fetch("id"),
            touch.fetch("cohort_id"),
            touch.fetch("cohort_name"),
            touch.fetch("title"),
            Date.parse(touch.fetch("date")),
            touch.fetch("owner"),
            touch.fetch("channel"),
            touch.fetch("notes"),
            DateTime.parse(touch.fetch("created_at"))
          ]
        )
      end
    end

    def schema_table(name)
      "#{DEFAULT_SCHEMA}.#{name}"
    end
  end
end
