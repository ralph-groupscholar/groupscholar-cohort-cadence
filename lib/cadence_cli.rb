# frozen_string_literal: true

require "date"
require_relative "cadence_store"
require_relative "cadence_db"

module GroupScholar
  class CadenceCLI
    def initialize(argv, root)
      @argv = argv.dup
      @root = root
      @store = CadenceStore.new(File.join(root, "data", "cadence.json"))
    end

    def run
      command = @argv.shift
      case command
      when "init"
        @store.init_store
        puts "Initialized cadence store at #{@store.path}."
      when "add-cohort"
        attrs = parse_options(%w[name start_date end_date size notes])
        cohort = @store.add_cohort(attrs)
        puts format_cohort(cohort)
      when "add-touchpoint"
        attrs = parse_options(%w[cohort title date owner channel notes])
        touchpoint = @store.add_touchpoint(attrs)
        puts format_touchpoint(touchpoint)
      when "list-cohorts"
        cohorts = @store.list_cohorts
        if cohorts.empty?
          puts "No cohorts yet."
        else
          cohorts.each { |cohort| puts format_cohort(cohort) }
        end
      when "upcoming"
        days = (option_value("days") || "30").to_i
        touchpoints = @store.upcoming(days)
        if touchpoints.empty?
          puts "No touchpoints in the next #{days} days."
        else
          touchpoints.each { |touch| puts format_touchpoint(touch) }
        end
      when "summary"
        days = (option_value("days") || "30").to_i
        summary = @store.summary(days)
        puts render_summary(summary)
      when "status"
        stale_days = (option_value("stale-days") || "21").to_i
        lookahead_days = (option_value("lookahead") || "30").to_i
        status = @store.cadence_status(stale_days, lookahead_days)
        puts render_status(status, stale_days, lookahead_days)
      when "gap-report"
        lookback = (option_value("lookback") || "30").to_i
        lookahead = (option_value("lookahead") || "30").to_i
        status_filter = option_value("status")
        report = @store.gap_report(lookback, lookahead)
        puts render_gap_report(report, status_filter)
      when "sync-db"
        data = @store.load_store
        db = CadenceDB.new
        db.sync!(data)
        puts "Synced #{data["cohorts"].size} cohorts and #{data["touchpoints"].size} touchpoints to Postgres."
      else
        puts usage
      end
    rescue StandardError => e
      warn "Error: #{e.message}"
      exit 1
    end

    private

    def parse_options(required_keys)
      opts = {}
      required_keys.each do |key|
        value = option_value(key.gsub("_", "-"))
        raise "Missing --#{key.gsub("_", "-")}" if value.nil? || value.strip.empty?
        opts[key] = value
      end
      opts
    end

    def option_value(flag)
      index = @argv.index("--#{flag}")
      return nil unless index
      @argv[index + 1]
    end

    def format_cohort(cohort)
      "#{cohort["name"]} (#{cohort["id"]}) | #{cohort["start_date"]} → #{cohort["end_date"]} | size #{cohort["size"]} | #{cohort["notes"]}"
    end

    def format_touchpoint(touch)
      "#{touch["date"]} | #{touch["title"]} | #{touch["cohort_name"]} | #{touch["owner"]} via #{touch["channel"]} | #{touch["notes"]}"
    end

    def render_summary(summary)
      lines = []
      lines << "# Cohort Cadence Summary"
      lines << "Generated: #{summary["generated_at"]}"
      lines << ""
      lines << "- Cohorts tracked: #{summary["cohort_count"]}"
      lines << "- Touchpoints logged: #{summary["touchpoint_count"]}"
      lines << "- Upcoming window: next #{summary["days"]} days"
      lines << ""
      if summary["upcoming"].empty?
        lines << "No upcoming touchpoints."
      else
        lines << "## Upcoming Touchpoints"
        summary["upcoming"].each do |touch|
          lines << "- #{format_touchpoint(touch)}"
        end
      end
      lines.join("\n")
    end

    def render_status(status, stale_days, lookahead_days)
      lines = []
      lines << "# Cohort Cadence Status"
      lines << "Generated: #{DateTime.now.iso8601}"
      lines << "Stale threshold: > #{stale_days} days without touchpoint"
      lines << "Lookahead window: #{lookahead_days} days"
      lines << ""

      if status.empty?
        lines << "No cohorts yet."
        return lines.join("\n")
      end

      status.each do |entry|
        cohort = entry["cohort"]
        last_touch = entry["last_touchpoint"]
        next_touch = entry["next_touchpoint"]
        lines << "## #{cohort["name"]} (#{cohort["id"]})"
        lines << "- Status: #{entry["status"]}"
        if entry["days_since_last"]
          lines << "- Days since last touchpoint: #{entry["days_since_last"]}"
        else
          lines << "- Days since last touchpoint: n/a"
        end
        if last_touch
          lines << "- Last touchpoint: #{format_touchpoint(last_touch)}"
        else
          lines << "- Last touchpoint: none"
        end
        if next_touch
          lines << "- Next touchpoint: #{format_touchpoint(next_touch)}"
        else
          lines << "- Next touchpoint: none"
        end
        if entry["stale"]
          lines << "- Attention: stale cadence (over #{entry["stale_days"]} days)"
        end
        if entry["next_within_lookahead"]
          lines << "- Upcoming within lookahead: yes"
        else
          lines << "- Upcoming within lookahead: no"
        end
        lines << ""
      end
      lines.join("\n").rstrip
    end

    def render_gap_report(report, status_filter)
      lines = []
      lines << "# Cohort Cadence Gap Report"
      lines << "Generated: #{report["generated_at"]}"
      lines << "Lookback: #{report["lookback_days"]} days | Lookahead: #{report["lookahead_days"]} days"
      lines << "Status filter: #{status_filter}" if status_filter
      lines << ""
      counts = report["counts"]
      lines << "- At-risk cohorts: #{counts.fetch("at-risk", 0)}"
      lines << "- Stale cohorts: #{counts.fetch("stale", 0)}"
      lines << "- Unscheduled cohorts: #{counts.fetch("unscheduled", 0)}"
      lines << "- On-track cohorts: #{counts.fetch("on-track", 0)}"
      lines << ""
      entries = report["entries"]
      if status_filter
        entries = entries.select { |entry| entry["status"] == status_filter }
      end
      if entries.empty?
        lines << "No cohorts match the current filter."
        return lines.join("\n").rstrip
      end
      entries.each do |entry|
        cohort = entry["cohort"]
        lines << "## #{cohort["name"]} (#{cohort["id"]})"
        lines << "Status: #{entry["status"]}"
        lines << "Last touchpoint: #{entry["last_touchpoint"] || "none"}"
        lines << "Next touchpoint: #{entry["next_touchpoint"] || "none"}"
        lines << "Days since last: #{entry["days_since_last"] || "n/a"}"
        lines << "Days until next: #{entry["days_until_next"] || "n/a"}"
        lines << ""
      end
      lines.join("\n").rstrip
    end

    def usage
      <<~TEXT
        Cohort Cadence CLI

        Commands:
          init
          add-cohort --name NAME --start-date YYYY-MM-DD --end-date YYYY-MM-DD --size N --notes "Notes"
          add-touchpoint --cohort COHORT_ID_OR_NAME --title TITLE --date YYYY-MM-DD --owner NAME --channel CHANNEL --notes "Notes"
          list-cohorts
          upcoming --days N
          summary --days N
          status --stale-days N --lookahead N
          gap-report --lookback N --lookahead N [--status at-risk|stale|unscheduled|on-track]
          sync-db
      TEXT
    end
  end
end
