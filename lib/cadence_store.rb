# frozen_string_literal: true

require "json"
require "date"

module GroupScholar
  class CadenceStore
    attr_reader :path

    def initialize(path)
      @path = path
    end

    def init_store
      data = {
        "meta" => {
          "created_at" => DateTime.now.iso8601,
          "version" => 1
        },
        "cohorts" => [],
        "touchpoints" => []
      }
      write(data)
    end

    def load_store
      raise_missing unless File.exist?(path)
      JSON.parse(File.read(path))
    end

    def save_store(data)
      write(data)
    end

    def add_cohort(attrs)
      data = load_store
      cohort = {
        "id" => generate_id("cohort"),
        "name" => attrs.fetch("name"),
        "start_date" => attrs.fetch("start_date"),
        "end_date" => attrs.fetch("end_date"),
        "size" => attrs.fetch("size"),
        "notes" => attrs.fetch("notes"),
        "created_at" => DateTime.now.iso8601
      }
      data["cohorts"] << cohort
      save_store(data)
      cohort
    end

    def add_touchpoint(attrs)
      data = load_store
      cohort = find_cohort(data, attrs.fetch("cohort"))
      touchpoint = {
        "id" => generate_id("touchpoint"),
        "cohort_id" => cohort["id"],
        "cohort_name" => cohort["name"],
        "title" => attrs.fetch("title"),
        "date" => attrs.fetch("date"),
        "owner" => attrs.fetch("owner"),
        "channel" => attrs.fetch("channel"),
        "notes" => attrs.fetch("notes"),
        "created_at" => DateTime.now.iso8601
      }
      data["touchpoints"] << touchpoint
      save_store(data)
      touchpoint
    end

    def list_cohorts
      data = load_store
      data["cohorts"].sort_by { |cohort| cohort["start_date"] }
    end

    def upcoming(days)
      data = load_store
      cutoff = Date.today + days
      data["touchpoints"].select do |touch|
        date = Date.parse(touch["date"])
        date >= Date.today && date <= cutoff
      end.sort_by { |touch| touch["date"] }
    end

    def summary(days)
      data = load_store
      upcoming_items = upcoming(days)
      {
        "generated_at" => DateTime.now.iso8601,
        "days" => days,
        "cohort_count" => data["cohorts"].size,
        "touchpoint_count" => data["touchpoints"].size,
        "upcoming" => upcoming_items
      }
    end

    def gap_report(lookback_days, lookahead_days)
      data = load_store
      today = Date.today
      entries = data["cohorts"].map do |cohort|
        touches = data["touchpoints"].select { |touch| touch["cohort_id"] == cohort["id"] }
        last_touch = touches.map { |touch| Date.parse(touch["date"]) }.select { |date| date <= today }.max
        next_touch = touches.map { |touch| Date.parse(touch["date"]) }.select { |date| date >= today }.min
        days_since_last = last_touch ? (today - last_touch).to_i : nil
        days_until_next = next_touch ? (next_touch - today).to_i : nil
        stale = last_touch.nil? || days_since_last > lookback_days
        unscheduled = next_touch.nil? || days_until_next > lookahead_days
        status = if stale && unscheduled
          "at-risk"
        elsif stale
          "stale"
        elsif unscheduled
          "unscheduled"
        else
          "on-track"
        end
        {
          "cohort" => cohort,
          "last_touchpoint" => last_touch&.iso8601,
          "next_touchpoint" => next_touch&.iso8601,
          "days_since_last" => days_since_last,
          "days_until_next" => days_until_next,
          "status" => status
        }
      end

      counts = entries.group_by { |entry| entry["status"] }.transform_values(&:size)
      {
        "generated_at" => DateTime.now.iso8601,
        "lookback_days" => lookback_days,
        "lookahead_days" => lookahead_days,
        "counts" => counts,
        "entries" => entries.sort_by { |entry| entry["cohort"]["start_date"] }
      }
    end

    def cadence_status(stale_days, lookahead_days)
      data = load_store
      grouped = data["touchpoints"].group_by { |touch| touch["cohort_id"] }
      today = Date.today
      lookahead_date = today + lookahead_days

      data["cohorts"].map do |cohort|
        touches = (grouped[cohort["id"]] || []).map do |touch|
          touch.merge("parsed_date" => Date.parse(touch["date"]))
        end
        past = touches.select { |touch| touch["parsed_date"] <= today }
        future = touches.select { |touch| touch["parsed_date"] >= today }
        last_touch = past.max_by { |touch| touch["parsed_date"] }
        next_touch = future.min_by { |touch| touch["parsed_date"] }
        start_date = Date.parse(cohort["start_date"])
        end_date = Date.parse(cohort["end_date"])

        status = if end_date < today
                   "ended"
                 elsif start_date > today
                   "upcoming"
                 else
                   "active"
                 end

        days_since_last = if last_touch
                            (today - last_touch["parsed_date"]).to_i
                          elsif start_date <= today
                            (today - start_date).to_i
                          end

        days_until_next = if next_touch
                            (next_touch["parsed_date"] - today).to_i
                          end

        {
          "cohort" => cohort,
          "status" => status,
          "last_touchpoint" => last_touch,
          "next_touchpoint" => next_touch,
          "days_since_last" => days_since_last,
          "days_until_next" => days_until_next,
          "next_within_lookahead" => next_touch && next_touch["parsed_date"] <= lookahead_date,
          "stale" => status == "active" && days_since_last && days_since_last > stale_days,
          "stale_days" => stale_days
        }
      end.sort_by do |entry|
        [
          entry["stale"] ? 0 : 1,
          entry["status"] == "active" ? 0 : (entry["status"] == "upcoming" ? 1 : 2),
          -(entry["days_since_last"] || -1)
        ]
      end
    end

    private

    def write(data)
      File.write(path, JSON.pretty_generate(data))
    end

    def raise_missing
      raise "No cadence store found at #{path}. Run `cohort-cadence init` first."
    end

    def find_cohort(data, identifier)
      cohort = data["cohorts"].find do |entry|
        entry["id"] == identifier || entry["name"].casecmp(identifier).zero?
      end
      raise "Unknown cohort: #{identifier}" unless cohort
      cohort
    end

    def generate_id(prefix)
      "#{prefix}-#{Time.now.to_i}-#{rand(1000..9999)}"
    end
  end
end
