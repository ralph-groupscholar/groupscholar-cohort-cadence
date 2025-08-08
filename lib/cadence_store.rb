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
