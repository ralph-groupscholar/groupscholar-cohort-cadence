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
      when "export-ics"
        days = (option_value("days") || "90").to_i
        output = option_value("output") || File.join(@root, "data", "cadence.ics")
        result = @store.export_ics(days, output)
        puts "Exported #{result["count"]} touchpoints to #{result["path"]} (next #{result["days"]} days)."
      when "owner-load"
        days = (option_value("days") || "30").to_i
        owner_filter = option_value("owner")
        report = @store.owner_load(days)
        puts render_owner_load(report, owner_filter)
      when "owner-balance"
        days = (option_value("days") || "30").to_i
        threshold_value = option_value("threshold")
        threshold = threshold_value ? threshold_value.to_f : 0.25
        report = @store.owner_balance(days, threshold)
        puts render_owner_balance(report)
      when "channel-report"
        lookback_days = (option_value("lookback") || "30").to_i
        lookahead_days = (option_value("lookahead") || "30").to_i
        owner_filter = option_value("owner")
        cohort_filter = option_value("cohort")
        report = @store.channel_report(lookback_days, lookahead_days, owner_filter, cohort_filter)
        puts render_channel_report(report)
      when "status"
        stale_days = (option_value("stale-days") || "21").to_i
        lookahead_days = (option_value("lookahead") || "30").to_i
        status = @store.cadence_status(stale_days, lookahead_days)
        puts render_status(status, stale_days, lookahead_days)
      when "cohort-report"
        lookback_days = (option_value("lookback") || "30").to_i
        lookahead_days = (option_value("lookahead") || "30").to_i
        cohort_id = option_value("cohort")
        raise "Missing --cohort" if cohort_id.nil? || cohort_id.strip.empty?
        report = @store.cohort_report(cohort_id, lookback_days, lookahead_days)
        puts render_cohort_report(report)
      when "gap-report"
        lookback = (option_value("lookback") || "30").to_i
        lookahead = (option_value("lookahead") || "30").to_i
        status_filter = option_value("status")
        validate_status_filter(status_filter)
        report = @store.gap_report(lookback, lookahead)
        puts render_gap_report(report, status_filter)
      when "cadence-metrics"
        max_gap_value = option_value("max-gap")
        max_gap_days = max_gap_value ? max_gap_value.to_i : nil
        report = @store.cadence_metrics(max_gap_days)
        puts render_cadence_metrics(report)
      when "weekly-agenda"
        weeks = (option_value("weeks") || "8").to_i
        owner_filter = option_value("owner")
        cohort_filter = option_value("cohort")
        report = @store.weekly_agenda(weeks, owner_filter, cohort_filter)
        puts render_weekly_agenda(report)
      when "coverage-report"
        weeks = (option_value("weeks") || "8").to_i
        cohort_filter = option_value("cohort")
        report = @store.cohort_coverage(weeks, cohort_filter)
        puts render_cohort_coverage(report)
      when "owner-capacity"
        weeks = (option_value("weeks") || "8").to_i
        limit_value = option_value("limit")
        weekly_limit = limit_value ? limit_value.to_i : nil
        owner_filter = option_value("owner")
        report = @store.owner_capacity(weeks, weekly_limit, owner_filter)
        puts render_owner_capacity(report)
      when "owner-conflicts"
        days = (option_value("days") || "30").to_i
        limit_value = option_value("limit")
        daily_limit = limit_value ? limit_value.to_i : 2
        owner_filter = option_value("owner")
        report = @store.owner_conflicts(days, daily_limit, owner_filter)
        puts render_owner_conflicts(report)
      when "action-plan"
        target_gap_days = (option_value("target-gap") || "21").to_i
        lookahead_days = (option_value("lookahead") || "30").to_i
        report = @store.action_plan(target_gap_days, lookahead_days)
        puts render_action_plan(report)
      when "db-summary"
        lookahead_days = (option_value("lookahead") || "30").to_i
        stale_days = (option_value("stale-days") || "21").to_i
        db = CadenceDB.new
        summary = db.summary(lookahead_days, stale_days)
        puts render_db_summary(summary, lookahead_days, stale_days)
      when "sync-db"
        data = @store.load_store
        db = CadenceDB.new
        db.sync!(data)
        puts "Synced #{data["cohorts"].size} cohorts and #{data["touchpoints"].size} touchpoints to Postgres."
      when "seed-db"
        db = CadenceDB.new
        result = db.seed!
        puts "Seeded Postgres with #{result["cohorts"]} cohorts and #{result["touchpoints"]} touchpoints."
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

    def render_owner_balance(report)
      lines = []
      lines << "# Owner Balance"
      lines << "Generated: #{report["generated_at"]}"
      lines << "Window: next #{report["days"]} days"
      lines << "Imbalance threshold: #{(report["threshold"] * 100).round(0)}%"
      lines << ""
      lines << "- Total touchpoints: #{report["total_touchpoints"]}"
      lines << "- Owners tracked: #{report["owners_count"]}"
      lines << "- Average per owner: #{report["avg_per_owner"] || "n/a"}"
      lines << "- Status counts: #{render_rollup(report["status_counts"])}"
      lines << ""

      if report["owners"].empty?
        lines << "No touchpoints in the next #{report["days"]} days."
        return lines.join("\n")
      end

      lines << "## Owner Workload"
      report["owners"].each do |owner|
        share = (owner["share"] * 100).round(1)
        delta = owner["delta_from_avg"] ? format("%+.2f", owner["delta_from_avg"]) : "n/a"
        lines << "- #{owner["owner"]}: #{owner["count"]} touchpoints (#{share}% share, Δ #{delta}) [#{owner["status"]}]"
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

    def render_owner_load(report, owner_filter)
      lines = []
      lines << "# Cohort Cadence Owner Load"
      lines << "Generated: #{report["generated_at"]}"
      lines << "Upcoming window: next #{report["days"]} days"
      lines << "Total touchpoints: #{report["total_touchpoints"]}"
      lines << ""
      owners = report["owners"]
      if owner_filter
        owners = owners.select { |entry| entry["owner"].downcase == owner_filter.downcase }
        lines << "Owner filter: #{owner_filter}"
        lines << "" if owners.any?
      end
      if owners.empty?
        lines << "No touchpoints in the current window."
        return lines.join("\n").rstrip
      end
      owners.each do |entry|
        lines << "## #{entry["owner"]} (#{entry["count"]})"
        if entry["channels"].any?
          channel_summary = entry["channels"].map { |channel, count| "#{channel}: #{count}" }.join(", ")
          lines << "- Channels: #{channel_summary}"
        end
        if entry["cohorts"].any?
          cohort_summary = entry["cohorts"].map { |cohort, count| "#{cohort}: #{count}" }.join(", ")
          lines << "- Cohorts: #{cohort_summary}"
        end
        entry["touchpoints"].each do |touch|
          lines << "- #{format_touchpoint(touch)}"
        end
        lines << ""
      end
      lines.join("\n").rstrip
    end

    def render_channel_report(report)
      lines = []
      lines << "# Channel Touchpoint Report"
      lines << "Generated: #{report["generated_at"]}"
      lines << "Window: #{report["window_start"]} → #{report["window_end"]} (lookback #{report["lookback_days"]} days, lookahead #{report["lookahead_days"]} days)"
      lines << "Total touchpoints: #{report["total_touchpoints"]}"
      if report["owner_filter"] && !report["owner_filter"].strip.empty?
        lines << "Owner filter: #{report["owner_filter"]}"
      end
      if report["cohort_filter"] && !report["cohort_filter"].strip.empty?
        lines << "Cohort filter: #{report["cohort_filter"]}"
      end
      lines << ""

      channels = report["channels"]
      if channels.empty?
        lines << "No touchpoints in the selected window."
        return lines.join("\n").rstrip
      end

      channels.each do |channel|
        lines << "## #{channel["channel"]} (#{channel["count"]})"
        lines << "- Past touchpoints: #{channel["past_count"]}"
        lines << "- Upcoming touchpoints: #{channel["upcoming_count"]}"
        if channel["last_touchpoint"]
          lines << "- Last touchpoint: #{format_touchpoint(channel["last_touchpoint"])}"
        else
          lines << "- Last touchpoint: none"
        end
        if channel["next_touchpoint"]
          lines << "- Next touchpoint: #{format_touchpoint(channel["next_touchpoint"])}"
        else
          lines << "- Next touchpoint: none"
        end
        lines << "- Owners: #{render_rollup(channel["owners"])}"
        lines << "- Cohorts: #{render_rollup(channel["cohorts"])}"
        channel["touchpoints"].each do |touch|
          lines << "- #{format_touchpoint(touch)}"
        end
        lines << ""
      end

      lines.join("\n").rstrip
    end

    def render_db_summary(summary, lookahead_days, stale_days)
      lines = []
      lines << "# Cohort Cadence DB Summary"
      lines << "Generated: #{summary["generated_at"]}"
      lines << "Lookahead: #{lookahead_days} days | Stale threshold: #{stale_days} days"
      lines << ""
      lines << "- Cohorts in DB: #{summary["cohort_count"]}"
      lines << "- Touchpoints in DB: #{summary["touchpoint_count"]}"
      if summary["last_sync"]
        lines << "- Last sync: #{summary["last_sync"]["synced_at"]} (#{summary["last_sync"]["cohorts_count"]} cohorts, #{summary["last_sync"]["touchpoints_count"]} touchpoints)"
      else
        lines << "- Last sync: none"
      end
      lines << ""
      if summary["upcoming"].empty?
        lines << "No upcoming touchpoints in the next #{lookahead_days} days."
      else
        lines << "## Upcoming Touchpoints"
        summary["upcoming"].each do |touch|
          lines << "- #{touch["date"]} | #{touch["title"]} | #{touch["cohort_name"]} | #{touch["owner"]} via #{touch["channel"]}"
        end
      end
      lines << ""
      if summary["stale_cohorts"].empty?
        lines << "No stale active cohorts."
      else
        lines << "## Stale Active Cohorts"
        summary["stale_cohorts"].each do |cohort|
          lines << "- #{cohort["name"]} (#{cohort["id"]}) | last touch: #{cohort["last_touchpoint"] || "none"} | days since: #{cohort["days_since_last"]}"
        end
      end
      lines.join("\n").rstrip
    end

    def render_cadence_metrics(report)
      lines = []
      lines << "# Cohort Cadence Metrics"
      lines << "Generated: #{report["generated_at"]}"
      if report["max_gap_days"]
        lines << "Gap flag threshold: > #{report["max_gap_days"]} days"
      else
        lines << "Gap flag threshold: none"
      end
      lines << ""
      lines << "- Cohorts tracked: #{report["cohort_count"]}"
      lines << "- Flagged cohorts: #{report["flagged_count"]}"
      lines << ""

      if report["entries"].empty?
        lines << "No cohorts yet."
        return lines.join("\n").rstrip
      end

      report["entries"].each do |entry|
        cohort = entry["cohort"]
        lines << "## #{cohort["name"]} (#{cohort["id"]})"
        lines << "- Touchpoints: #{entry["touchpoint_count"]}"
        lines << "- Avg gap: #{entry["avg_gap_days"] || "n/a"} days"
        lines << "- Min gap: #{entry["min_gap_days"] || "n/a"} days"
        lines << "- Max gap: #{entry["max_gap_days"] || "n/a"} days"
        lines << "- Flagged: #{entry["gap_flag"] ? "yes" : "no"}"
        if entry["last_touchpoint"]
          lines << "- Last touchpoint: #{format_touchpoint(entry["last_touchpoint"])}"
          lines << "- Days since last: #{entry["days_since_last"]}"
        else
          lines << "- Last touchpoint: none"
          lines << "- Days since last: n/a"
        end
        if entry["next_touchpoint"]
          lines << "- Next touchpoint: #{format_touchpoint(entry["next_touchpoint"])}"
          lines << "- Days until next: #{entry["days_until_next"]}"
        else
          lines << "- Next touchpoint: none"
          lines << "- Days until next: n/a"
        end
        lines << ""
      end
      lines.join("\n").rstrip
    end

    def render_weekly_agenda(report)
      lines = []
      lines << "# Cohort Cadence Weekly Agenda"
      lines << "Generated: #{report["generated_at"]}"
      lines << "Window: #{report["window_start"]} → #{report["window_end"]} (#{report["weeks"]} weeks)"
      lines << "Total touchpoints: #{report["total_touchpoints"]}"
      if report["owner_filter"] && !report["owner_filter"].strip.empty?
        lines << "Owner filter: #{report["owner_filter"]}"
      end
      if report["cohort_filter"] && !report["cohort_filter"].strip.empty?
        lines << "Cohort filter: #{report["cohort_filter"]}"
      end
      lines << ""

      weeks_list = report["weeks_list"]
      if weeks_list.empty?
        lines << "No touchpoints scheduled in the current window."
        return lines.join("\n").rstrip
      end

      weeks_list.each do |week|
        lines << "## Week of #{week["week_start"]} (#{week["week_start"]} → #{week["week_end"]})"
        week["touchpoints"].each do |touch|
          lines << "- #{format_touchpoint(touch)}"
        end
        lines << ""
      end

      lines.join("\n").rstrip
    end

    def render_cohort_coverage(report)
      lines = []
      lines << "# Cohort Coverage Report"
      lines << "Generated: #{report["generated_at"]}"
      lines << "Window: #{report["window_start"]} → #{report["window_end"]} (#{report["weeks"]} weeks)"
      lines << "- Cohorts tracked: #{report["cohort_count"]}"
      lines << "- Weeks tracked: #{report["weeks_tracked"]}"
      lines << ""

      if report["entries"].empty?
        lines << "No cohorts found for this window."
        return lines.join("\n").rstrip
      end

      report["entries"].each do |entry|
        cohort = entry["cohort"]
        coverage_pct = (entry["coverage_rate"] * 100).round(1)
        lines << "## #{cohort["name"]} (#{cohort["id"]})"
        lines << "- Touchpoints in window: #{entry["total_touchpoints"]}"
        lines << "- Coverage: #{coverage_pct}% (#{entry["weeks_with_touchpoints"]}/#{entry["weeks_tracked"]} weeks)"
        lines << "- Longest gap: #{entry["longest_gap_weeks"]} weeks"
        if entry["empty_weeks"].empty?
          lines << "- Empty weeks: none"
        else
          empty_ranges = entry["empty_weeks"].map do |week|
            "#{week["week_start"]}→#{week["week_end"]}"
          end
          lines << "- Empty weeks: #{empty_ranges.join(", ")}"
        end
        lines << "### Weekly Counts"
        entry["weeks"].each do |week|
          label = "#{week["week_start"]}→#{week["week_end"]}"
          lines << "- #{label}: #{week["count"]} touchpoints"
        end
        lines << ""
      end

      lines.join("\n").rstrip
    end

    def render_owner_capacity(report)
      lines = []
      lines << "# Cohort Cadence Owner Capacity"
      lines << "Generated: #{report["generated_at"]}"
      lines << "Window: #{report["window_start"]} → #{report["window_end"]} (#{report["weeks"]} weeks)"
      if report["weekly_limit"]
        lines << "Weekly limit: #{report["weekly_limit"]} touchpoints per owner"
      else
        lines << "Weekly limit: none"
      end
      lines << "Total touchpoints: #{report["total_touchpoints"]}"
      lines << "Owners tracked: #{report["owners_count"]}"
      lines << "Over-limit weeks: #{report["over_limit_weeks"]}"
      if report["owner_filter"] && !report["owner_filter"].strip.empty?
        lines << "Owner filter: #{report["owner_filter"]}"
      end
      lines << ""

      owners = report["owners"]
      if owners.empty?
        lines << "No touchpoints scheduled in the current window."
        return lines.join("\n").rstrip
      end

      owners.each do |owner|
        lines << "## #{owner["owner"]} (#{owner["total_touchpoints"]})"
        lines << "- Weeks tracked: #{owner["weeks_tracked"]}"
        lines << "- Over-limit weeks: #{owner["over_limit_weeks"]}"
        owner["weeks"].each do |week|
          label = "Week of #{week["week_start"]} (#{week["week_start"]} → #{week["week_end"]})"
          status = week["over_limit"] ? "OVER LIMIT" : "ok"
          lines << "- #{label}: #{week["count"]} touchpoints (#{status})"
          week["touchpoints"].each do |touch|
            lines << "  - #{format_touchpoint(touch)}"
          end
        end
        lines << ""
      end

      lines.join("\n").rstrip
    end

    def render_owner_conflicts(report)
      lines = []
      lines << "# Cohort Cadence Owner Conflicts"
      lines << "Generated: #{report["generated_at"]}"
      lines << "Window: #{report["window_start"]} → #{report["window_end"]} (#{report["days"]} days)"
      lines << "Daily limit: #{report["daily_limit"]} touchpoints per owner"
      lines << "Total touchpoints: #{report["total_touchpoints"]}"
      lines << "Owners with conflicts: #{report["owners_count"]}"
      lines << "Conflict days: #{report["conflict_days"]}"
      if report["owner_filter"] && !report["owner_filter"].strip.empty?
        lines << "Owner filter: #{report["owner_filter"]}"
      end
      lines << ""

      owners = report["owners"]
      if owners.empty?
        lines << "No owner conflicts in the current window."
        return lines.join("\n").rstrip
      end

      owners.each do |owner|
        lines << "## #{owner["owner"]} (#{owner["conflict_days"]} conflict days)"
        owner["days"].each do |day|
          lines << "- #{day["date"]}: #{day["count"]} touchpoints"
          day["touchpoints"].each do |touch|
            lines << "  - #{format_touchpoint(touch)}"
          end
        end
        lines << ""
      end

      lines.join("\n").rstrip
    end

    def render_action_plan(report)
      lines = []
      lines << "# Cohort Cadence Action Plan"
      lines << "Generated: #{report["generated_at"]}"
      lines << "Target gap: #{report["target_gap_days"]} days | Lookahead: #{report["lookahead_days"]} days"
      lines << ""
      lines << "- Cohorts tracked: #{report["cohort_count"]}"
      lines << "- Action needed: #{report["action_count"]}"
      lines << ""

      entries = report["entries"]
      if entries.empty?
        lines << "No cohorts need new touchpoints in the current window."
        return lines.join("\n").rstrip
      end

      entries.each do |entry|
        cohort = entry["cohort"]
        lines << "## #{cohort["name"]} (#{cohort["id"]})"
        lines << "- Status: #{entry["status"]}"
        if entry["last_touchpoint"]
          lines << "- Last touchpoint: #{format_touchpoint(entry["last_touchpoint"])}"
          lines << "- Days since last: #{entry["days_since_last"]}"
        else
          lines << "- Last touchpoint: none"
          lines << "- Days since last: n/a"
        end
        if entry["next_touchpoint"]
          lines << "- Next touchpoint: #{format_touchpoint(entry["next_touchpoint"])}"
          lines << "- Days until next: #{entry["days_until_next"]}"
        else
          lines << "- Next touchpoint: none"
          lines << "- Days until next: n/a"
        end
        lines << "- Recommended date: #{entry["recommended_date"] || "n/a"}"
        lines << "- Recommended owner: #{entry["recommended_owner"]}"
        lines << "- Reason: #{entry["reason"]}"
        lines << "- Within lookahead: #{entry["within_lookahead"] ? "yes" : "no"}"
        lines << ""
      end

      lines.join("\n").rstrip
    end

    def render_cohort_report(report)
      cohort = report["cohort"]
      lines = []
      lines << "# Cohort Cadence Report"
      lines << "Generated: #{report["generated_at"]}"
      lines << "Cohort: #{cohort["name"]} (#{cohort["id"]})"
      lines << "Window: lookback #{report["lookback_days"]} days | lookahead #{report["lookahead_days"]} days"
      lines << ""
      lines << "- Total touchpoints: #{report["touchpoint_count"]}"
      if report["last_touchpoint"]
        lines << "- Last touchpoint: #{format_touchpoint(report["last_touchpoint"])}"
        lines << "- Days since last: #{report["days_since_last"]}"
      else
        lines << "- Last touchpoint: none"
        lines << "- Days since last: n/a"
      end
      if report["next_touchpoint"]
        lines << "- Next touchpoint: #{format_touchpoint(report["next_touchpoint"])}"
        lines << "- Days until next: #{report["days_until_next"]}"
      else
        lines << "- Next touchpoint: none"
        lines << "- Days until next: n/a"
      end
      lines << ""
      if report["recent_touchpoints"].empty?
        lines << "No touchpoints in the last #{report["lookback_days"]} days."
      else
        lines << "## Recent Touchpoints (last #{report["lookback_days"]} days)"
        report["recent_touchpoints"].each do |touch|
          lines << "- #{format_touchpoint(touch)}"
        end
      end
      lines << ""
      if report["upcoming_touchpoints"].empty?
        lines << "No touchpoints scheduled in the next #{report["lookahead_days"]} days."
      else
        lines << "## Upcoming Touchpoints (next #{report["lookahead_days"]} days)"
        report["upcoming_touchpoints"].each do |touch|
          lines << "- #{format_touchpoint(touch)}"
        end
      end
      lines.join("\n").rstrip
    end

    def render_rollup(counts)
      return "none" if counts.nil? || counts.empty?
      counts.sort_by { |key, value| [-value, key.to_s] }
            .map { |key, value| "#{key} (#{value})" }
            .join(", ")
    end

    def validate_status_filter(status_filter)
      return if status_filter.nil?
      allowed = %w[at-risk stale unscheduled on-track]
      return if allowed.include?(status_filter)
      raise "Invalid --status #{status_filter}. Use one of: #{allowed.join(", ")}"
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
          export-ics --days N [--output PATH]
          owner-load --days N [--owner NAME]
          owner-balance --days N [--threshold FLOAT]
          channel-report --lookback N --lookahead N [--owner NAME] [--cohort COHORT_ID_OR_NAME]
          status --stale-days N --lookahead N
          cohort-report --cohort COHORT_ID_OR_NAME --lookback N --lookahead N
          gap-report --lookback N --lookahead N [--status at-risk|stale|unscheduled|on-track]
          weekly-agenda --weeks N [--owner NAME] [--cohort COHORT_ID_OR_NAME]
          coverage-report --weeks N [--cohort COHORT_ID_OR_NAME]
          owner-capacity --weeks N [--limit N] [--owner NAME]
          owner-conflicts --days N [--limit N] [--owner NAME]
          action-plan --target-gap N --lookahead N
          cadence-metrics [--max-gap N]
          db-summary --stale-days N --lookahead N
          sync-db
          seed-db
      TEXT
    end
  end
end
