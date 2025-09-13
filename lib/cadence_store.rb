# frozen_string_literal: true

require "json"
require "date"
require "fileutils"

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

    def export_ics(days, output_path)
      upcoming_items = upcoming(days)
      calendar = build_ics(upcoming_items)
      FileUtils.mkdir_p(File.dirname(output_path))
      File.write(output_path, calendar)
      {
        "path" => output_path,
        "count" => upcoming_items.size,
        "days" => days
      }
    end

    def owner_load(days)
      data = load_store
      cutoff = Date.today + days
      windowed = data["touchpoints"].select do |touch|
        date = Date.parse(touch["date"])
        date >= Date.today && date <= cutoff
      end
      grouped = windowed.group_by do |touch|
        owner = touch["owner"].to_s.strip
        owner.empty? ? "Unassigned" : owner
      end
      owners = grouped.map do |owner, touches|
        channel_counts = touches.group_by { |touch| touch["channel"] }.transform_values(&:size)
        cohort_counts = touches.group_by { |touch| touch["cohort_name"] }.transform_values(&:size)
        {
          "owner" => owner,
          "count" => touches.size,
          "channels" => channel_counts,
          "cohorts" => cohort_counts,
          "touchpoints" => touches.sort_by { |touch| touch["date"] }
        }
      end
      {
        "generated_at" => DateTime.now.iso8601,
        "days" => days,
        "total_touchpoints" => windowed.size,
        "owners" => owners.sort_by { |entry| [-entry["count"], entry["owner"]] }
      }
    end

    def owner_balance(days, threshold = 0.25)
      data = load_store
      cutoff = Date.today + days
      windowed = data["touchpoints"].select do |touch|
        date = Date.parse(touch["date"])
        date >= Date.today && date <= cutoff
      end

      grouped = windowed.group_by do |touch|
        owner = touch["owner"].to_s.strip
        owner.empty? ? "Unassigned" : owner
      end

      owners_count = grouped.size
      total = windowed.size
      avg = owners_count.positive? ? (total.to_f / owners_count).round(2) : nil

      owners = grouped.map do |owner, touches|
        count = touches.size
        share = total.positive? ? (count.to_f / total).round(3) : 0.0
        delta = avg ? (count - avg).round(2) : nil
        status = if avg && threshold
                   if count > (avg * (1 + threshold))
                     "overloaded"
                   elsif count < (avg * (1 - threshold))
                     "underloaded"
                   else
                     "balanced"
                   end
                 else
                   "balanced"
                 end
        {
          "owner" => owner,
          "count" => count,
          "share" => share,
          "delta_from_avg" => delta,
          "status" => status,
          "touchpoints" => touches.sort_by { |touch| touch["date"] }
        }
      end

      status_counts = owners.group_by { |entry| entry["status"] }.transform_values(&:size)

      {
        "generated_at" => DateTime.now.iso8601,
        "days" => days,
        "threshold" => threshold,
        "total_touchpoints" => total,
        "owners_count" => owners_count,
        "avg_per_owner" => avg,
        "status_counts" => status_counts,
        "owners" => owners.sort_by { |entry| [-entry["count"], entry["owner"]] }
      }
    end

    def channel_report(lookback_days, lookahead_days, owner_filter = nil, cohort_filter = nil)
      data = load_store
      today = Date.today
      start_date = today - lookback_days
      end_date = today + lookahead_days
      windowed = data["touchpoints"].select do |touch|
        date = Date.parse(touch["date"])
        date >= start_date && date <= end_date
      end

      if owner_filter && !owner_filter.strip.empty?
        windowed = windowed.select do |touch|
          touch["owner"].to_s.strip.casecmp(owner_filter.strip).zero?
        end
      end

      if cohort_filter && !cohort_filter.strip.empty?
        windowed = windowed.select do |touch|
          touch["cohort_id"] == cohort_filter ||
            touch["cohort_name"].to_s.strip.casecmp(cohort_filter.strip).zero?
        end
      end

      grouped = windowed.group_by do |touch|
        channel = touch["channel"].to_s.strip
        channel.empty? ? "Unspecified" : channel
      end

      channels = grouped.map do |channel, touches|
        parsed = touches.map { |touch| touch.merge("parsed_date" => Date.parse(touch["date"])) }
        past = parsed.select { |touch| touch["parsed_date"] < today }
        upcoming = parsed.select { |touch| touch["parsed_date"] >= today }
        last_touch = past.max_by { |touch| touch["parsed_date"] }
        next_touch = upcoming.min_by { |touch| touch["parsed_date"] }
        owner_counts = touches.group_by do |touch|
          owner = touch["owner"].to_s.strip
          owner.empty? ? "Unassigned" : owner
        end.transform_values(&:size)
        cohort_counts = touches.group_by { |touch| touch["cohort_name"] }.transform_values(&:size)
        {
          "channel" => channel,
          "count" => touches.size,
          "past_count" => past.size,
          "upcoming_count" => upcoming.size,
          "last_touchpoint" => last_touch,
          "next_touchpoint" => next_touch,
          "owners" => owner_counts,
          "cohorts" => cohort_counts,
          "touchpoints" => touches.sort_by { |touch| touch["date"] }
        }
      end

      {
        "generated_at" => DateTime.now.iso8601,
        "lookback_days" => lookback_days,
        "lookahead_days" => lookahead_days,
        "window_start" => start_date.iso8601,
        "window_end" => end_date.iso8601,
        "total_touchpoints" => windowed.size,
        "owner_filter" => owner_filter,
        "cohort_filter" => cohort_filter,
        "channels" => channels.sort_by { |entry| [-entry["count"], entry["channel"]] }
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

    def cohort_report(identifier, lookback_days, lookahead_days)
      data = load_store
      cohort = find_cohort(data, identifier)
      today = Date.today
      lookback_start = today - lookback_days
      lookahead_end = today + lookahead_days

      touches = data["touchpoints"].select { |touch| touch["cohort_id"] == cohort["id"] }.map do |touch|
        touch.merge("parsed_date" => Date.parse(touch["date"]))
      end

      last_touch = touches.select { |touch| touch["parsed_date"] <= today }.max_by { |touch| touch["parsed_date"] }
      next_touch = touches.select { |touch| touch["parsed_date"] >= today }.min_by { |touch| touch["parsed_date"] }

      recent = touches.select { |touch| touch["parsed_date"] >= lookback_start && touch["parsed_date"] <= today }
      upcoming = touches.select { |touch| touch["parsed_date"] >= today && touch["parsed_date"] <= lookahead_end }

      {
        "generated_at" => DateTime.now.iso8601,
        "cohort" => cohort,
        "lookback_days" => lookback_days,
        "lookahead_days" => lookahead_days,
        "touchpoint_count" => touches.size,
        "last_touchpoint" => strip_parsed(last_touch),
        "next_touchpoint" => strip_parsed(next_touch),
        "days_since_last" => last_touch ? (today - last_touch["parsed_date"]).to_i : nil,
        "days_until_next" => next_touch ? (next_touch["parsed_date"] - today).to_i : nil,
        "recent_touchpoints" => strip_parsed_list(recent.sort_by { |touch| touch["parsed_date"] }),
        "upcoming_touchpoints" => strip_parsed_list(upcoming.sort_by { |touch| touch["parsed_date"] })
      }
    end

    def cadence_metrics(max_gap_days)
      data = load_store
      today = Date.today

      entries = data["cohorts"].map do |cohort|
        touches = data["touchpoints"].select { |touch| touch["cohort_id"] == cohort["id"] }.map do |touch|
          touch.merge("parsed_date" => Date.parse(touch["date"]))
        end.sort_by { |touch| touch["parsed_date"] }

        gaps = []
        touches.each_cons(2) do |first_touch, second_touch|
          gaps << (second_touch["parsed_date"] - first_touch["parsed_date"]).to_i
        end

        last_touch = touches.select { |touch| touch["parsed_date"] <= today }.max_by { |touch| touch["parsed_date"] }
        next_touch = touches.select { |touch| touch["parsed_date"] >= today }.min_by { |touch| touch["parsed_date"] }

        avg_gap = gaps.any? ? (gaps.sum.to_f / gaps.size).round(1) : nil
        max_gap = gaps.max
        min_gap = gaps.min

        {
          "cohort" => cohort,
          "touchpoint_count" => touches.size,
          "avg_gap_days" => avg_gap,
          "min_gap_days" => min_gap,
          "max_gap_days" => max_gap,
          "last_touchpoint" => strip_parsed(last_touch),
          "next_touchpoint" => strip_parsed(next_touch),
          "days_since_last" => last_touch ? (today - last_touch["parsed_date"]).to_i : nil,
          "days_until_next" => next_touch ? (next_touch["parsed_date"] - today).to_i : nil,
          "gap_flag" => max_gap_days && max_gap ? max_gap > max_gap_days : false
        }
      end

      flagged = entries.count { |entry| entry["gap_flag"] }

      {
        "generated_at" => DateTime.now.iso8601,
        "max_gap_days" => max_gap_days,
        "cohort_count" => entries.size,
        "flagged_count" => flagged,
        "entries" => entries.sort_by do |entry|
          [
            entry["gap_flag"] ? 0 : 1,
            -(entry["max_gap_days"] || -1),
            entry["cohort"]["start_date"]
          ]
        end
      }
    end

    def action_plan(target_gap_days, lookahead_days)
      data = load_store
      today = Date.today
      lookahead_end = today + lookahead_days

      entries = data["cohorts"].map do |cohort|
        touches = data["touchpoints"].select { |touch| touch["cohort_id"] == cohort["id"] }.map do |touch|
          touch.merge("parsed_date" => Date.parse(touch["date"]))
        end.sort_by { |touch| touch["parsed_date"] }

        last_touch = touches.select { |touch| touch["parsed_date"] <= today }.max_by { |touch| touch["parsed_date"] }
        next_touch = touches.select { |touch| touch["parsed_date"] >= today }.min_by { |touch| touch["parsed_date"] }
        start_date = Date.parse(cohort["start_date"])
        end_date = Date.parse(cohort["end_date"])

        status = if end_date < today
                   "ended"
                 elsif start_date > today
                   "upcoming"
                 else
                   "active"
                 end

        days_since_last = last_touch ? (today - last_touch["parsed_date"]).to_i : nil
        days_until_next = next_touch ? (next_touch["parsed_date"] - today).to_i : nil

        action_needed = false
        reason = nil
        recommended_date = nil

        if status == "active"
          if next_touch && days_until_next && days_until_next <= target_gap_days
            action_needed = false
          else
            action_needed = true
            reason = next_touch ? "next touchpoint beyond target gap" : "no upcoming touchpoint"
          end

          base_date = last_touch ? last_touch["parsed_date"] + target_gap_days : today
          recommended_date = [base_date, today].max
        elsif status == "upcoming"
          target_start = start_date + target_gap_days
          if next_touch && next_touch["parsed_date"] <= target_start
            action_needed = false
          else
            action_needed = true
            reason = next_touch ? "first touchpoint beyond target gap" : "no kickoff scheduled"
            recommended_date = start_date
          end
        end

        {
          "cohort" => cohort,
          "status" => status,
          "last_touchpoint" => strip_parsed(last_touch),
          "next_touchpoint" => strip_parsed(next_touch),
          "days_since_last" => days_since_last,
          "days_until_next" => days_until_next,
          "recommended_date" => recommended_date&.iso8601,
          "recommended_owner" => recommended_owner(touches, last_touch),
          "action_needed" => action_needed,
          "reason" => reason,
          "within_lookahead" => recommended_date ? (recommended_date <= lookahead_end) : false
        }
      end

      action_entries = entries.select { |entry| entry["action_needed"] }

      {
        "generated_at" => DateTime.now.iso8601,
        "target_gap_days" => target_gap_days,
        "lookahead_days" => lookahead_days,
        "cohort_count" => entries.size,
        "action_count" => action_entries.size,
        "entries" => action_entries.sort_by do |entry|
          [
            entry["within_lookahead"] ? 0 : 1,
            entry["recommended_date"] || "9999-12-31",
            entry["cohort"]["start_date"]
          ]
        end
      }
    end

    def weekly_agenda(weeks, owner_filter = nil, cohort_filter = nil)
      data = load_store
      today = Date.today
      end_date = today + (weeks * 7) - 1
      touches = data["touchpoints"].select do |touch|
        date = Date.parse(touch["date"])
        date >= today && date <= end_date
      end

      if owner_filter && !owner_filter.strip.empty?
        touches = touches.select do |touch|
          touch["owner"].to_s.strip.casecmp(owner_filter.strip).zero?
        end
      end

      if cohort_filter && !cohort_filter.strip.empty?
        touches = touches.select do |touch|
          touch["cohort_id"] == cohort_filter ||
            touch["cohort_name"].to_s.strip.casecmp(cohort_filter.strip).zero?
        end
      end

      grouped = touches.group_by do |touch|
        date = Date.parse(touch["date"])
        date - (date.cwday - 1)
      end

      weeks_list = grouped.map do |week_start, items|
        {
          "week_start" => week_start.iso8601,
          "week_end" => (week_start + 6).iso8601,
          "touchpoints" => items.sort_by { |touch| touch["date"] }
        }
      end.sort_by { |entry| entry["week_start"] }

      {
        "generated_at" => DateTime.now.iso8601,
        "weeks" => weeks,
        "window_start" => today.iso8601,
        "window_end" => end_date.iso8601,
        "total_touchpoints" => touches.size,
        "owner_filter" => owner_filter,
        "cohort_filter" => cohort_filter,
        "weeks_list" => weeks_list
      }
    end

    def cohort_coverage(weeks, cohort_filter = nil)
      data = load_store
      today = Date.today
      week_start = today - (today.cwday - 1)
      end_date = week_start + (weeks * 7) - 1
      week_starts = Array.new(weeks) { |index| week_start + (index * 7) }

      cohorts = data["cohorts"]
      if cohort_filter && !cohort_filter.strip.empty?
        filter = cohort_filter.strip
        cohorts = cohorts.select do |cohort|
          cohort["id"] == filter || cohort["name"].to_s.strip.casecmp(filter).zero?
        end
      end

      touches = data["touchpoints"].select do |touch|
        date = Date.parse(touch["date"])
        date >= today && date <= end_date
      end

      entries = cohorts.map do |cohort|
        cohort_touches = touches.select { |touch| touch["cohort_id"] == cohort["id"] }
        weeks_list = week_starts.map do |week_cursor|
          week_end = week_cursor + 6
          week_items = cohort_touches.select do |touch|
            date = Date.parse(touch["date"])
            date >= week_cursor && date <= week_end
          end
          {
            "week_start" => week_cursor.iso8601,
            "week_end" => week_end.iso8601,
            "count" => week_items.size,
            "touchpoints" => week_items.sort_by { |touch| touch["date"] }
          }
        end

        weeks_with = weeks_list.count { |entry| entry["count"] > 0 }
        weeks_tracked = weeks_list.size
        weeks_without = weeks_tracked - weeks_with
        coverage_rate = weeks_tracked.positive? ? (weeks_with.to_f / weeks_tracked).round(3) : 0.0

        longest_gap = 0
        current_gap = 0
        weeks_list.each do |entry|
          if entry["count"].zero?
            current_gap += 1
            longest_gap = [longest_gap, current_gap].max
          else
            current_gap = 0
          end
        end

        {
          "cohort" => cohort,
          "total_touchpoints" => cohort_touches.size,
          "weeks_tracked" => weeks_tracked,
          "weeks_with_touchpoints" => weeks_with,
          "weeks_without_touchpoints" => weeks_without,
          "coverage_rate" => coverage_rate,
          "longest_gap_weeks" => longest_gap,
          "empty_weeks" => weeks_list.select { |entry| entry["count"].zero? },
          "weeks" => weeks_list
        }
      end

      {
        "generated_at" => DateTime.now.iso8601,
        "weeks" => weeks,
        "window_start" => today.iso8601,
        "window_end" => end_date.iso8601,
        "cohort_filter" => cohort_filter,
        "cohort_count" => entries.size,
        "weeks_tracked" => week_starts.size,
        "entries" => entries.sort_by { |entry| [entry["weeks_with_touchpoints"], entry["cohort"]["start_date"]] }
      }
    end

    def owner_capacity(weeks, weekly_limit, owner_filter = nil)
      data = load_store
      today = Date.today
      end_date = today + (weeks * 7) - 1
      week_start = today - (today.cwday - 1)
      week_starts = []
      while week_start <= end_date
        week_starts << week_start
        week_start += 7
      end
      touches = data["touchpoints"].select do |touch|
        date = Date.parse(touch["date"])
        date >= today && date <= end_date
      end

      if owner_filter && !owner_filter.strip.empty?
        touches = touches.select do |touch|
          touch["owner"].to_s.strip.casecmp(owner_filter.strip).zero?
        end
      end

      grouped = touches.group_by do |touch|
        owner = touch["owner"].to_s.strip
        owner.empty? ? "Unassigned" : owner
      end

      owners = grouped.map do |owner, items|
        weeks_list = week_starts.map do |week_cursor|
          week_end = week_cursor + 6
          week_items = items.select do |touch|
            date = Date.parse(touch["date"])
            date >= week_cursor && date <= week_end
          end
          count = week_items.size
          {
            "week_start" => week_cursor.iso8601,
            "week_end" => week_end.iso8601,
            "count" => count,
            "over_limit" => weekly_limit ? count > weekly_limit : false,
            "touchpoints" => week_items.sort_by { |touch| touch["date"] }
          }
        end

        over_limit_weeks = weeks_list.count { |entry| entry["over_limit"] }

        {
          "owner" => owner,
          "total_touchpoints" => items.size,
          "weeks_tracked" => weeks_list.size,
          "over_limit_weeks" => over_limit_weeks,
          "weeks" => weeks_list
        }
      end

      total_over_limit_weeks = owners.sum { |entry| entry["over_limit_weeks"] }

      {
        "generated_at" => DateTime.now.iso8601,
        "weeks" => weeks,
        "window_start" => today.iso8601,
        "window_end" => end_date.iso8601,
        "weekly_limit" => weekly_limit,
        "owner_filter" => owner_filter,
        "total_touchpoints" => touches.size,
        "owners_count" => owners.size,
        "over_limit_weeks" => total_over_limit_weeks,
        "owners" => owners.sort_by { |entry| [-entry["total_touchpoints"], entry["owner"]] }
      }
    end

    def owner_conflicts(days, daily_limit, owner_filter = nil)
      data = load_store
      today = Date.today
      end_date = today + days
      touches = data["touchpoints"].select do |touch|
        date = Date.parse(touch["date"])
        date >= today && date <= end_date
      end

      if owner_filter && !owner_filter.strip.empty?
        touches = touches.select do |touch|
          touch["owner"].to_s.strip.casecmp(owner_filter.strip).zero?
        end
      end

      grouped = touches.group_by do |touch|
        owner = touch["owner"].to_s.strip
        owner.empty? ? "Unassigned" : owner
      end

      owners = grouped.map do |owner, items|
        day_groups = items.group_by { |touch| Date.parse(touch["date"]) }
        conflict_days = day_groups.map do |date, day_items|
          count = day_items.size
          {
            "date" => date.iso8601,
            "count" => count,
            "over_limit" => count > daily_limit,
            "touchpoints" => day_items.sort_by { |touch| touch["date"] }
          }
        end.select { |entry| entry["over_limit"] }
                     .sort_by { |entry| entry["date"] }

        {
          "owner" => owner,
          "total_touchpoints" => items.size,
          "conflict_days" => conflict_days.size,
          "days" => conflict_days
        }
      end.select { |entry| entry["conflict_days"] > 0 }

      total_conflict_days = owners.sum { |entry| entry["conflict_days"] }

      {
        "generated_at" => DateTime.now.iso8601,
        "days" => days,
        "window_start" => today.iso8601,
        "window_end" => end_date.iso8601,
        "daily_limit" => daily_limit,
        "owner_filter" => owner_filter,
        "total_touchpoints" => touches.size,
        "owners_count" => owners.size,
        "conflict_days" => total_conflict_days,
        "owners" => owners.sort_by { |entry| [-entry["conflict_days"], -entry["total_touchpoints"], entry["owner"]] }
      }
    end

    private

    def build_ics(touchpoints)
      lines = []
      lines << "BEGIN:VCALENDAR"
      lines << "VERSION:2.0"
      lines << "PRODID:-//Group Scholar//Cohort Cadence//EN"
      lines << "CALSCALE:GREGORIAN"
      touchpoints.each do |touch|
        date = Date.parse(touch["date"])
        lines << "BEGIN:VEVENT"
        lines << "UID:#{touch["id"]}@groupscholar-cohort-cadence"
        lines << "DTSTAMP:#{Time.now.utc.strftime("%Y%m%dT%H%M%SZ")}"
        lines << "DTSTART;VALUE=DATE:#{date.strftime("%Y%m%d")}"
        lines << "DTEND;VALUE=DATE:#{(date + 1).strftime("%Y%m%d")}"
        lines << "SUMMARY:#{ics_escape("#{touch["title"]} (#{touch["cohort_name"]})")}"
        lines << "DESCRIPTION:#{ics_escape(ics_description(touch))}"
        lines << "LOCATION:#{ics_escape(touch["channel"])}"
        lines << "END:VEVENT"
      end
      lines << "END:VCALENDAR"
      lines.join("\r\n") + "\r\n"
    end

    def ics_description(touch)
      [
        "Cohort: #{touch["cohort_name"]}",
        "Owner: #{touch["owner"]}",
        "Channel: #{touch["channel"]}",
        "Notes: #{touch["notes"]}"
      ].join("\n")
    end

    def ics_escape(value)
      return "" if value.nil?
      value.to_s.gsub("\\", "\\\\").gsub("\n", "\\n").gsub(",", "\\,").gsub(";", "\\;")
    end

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

    def strip_parsed(touch)
      return nil unless touch
      touch.reject { |key, _| key == "parsed_date" }
    end

    def strip_parsed_list(touches)
      touches.map { |touch| strip_parsed(touch) }
    end

    def recommended_owner(touches, last_touch)
      if last_touch
        owner = last_touch["owner"].to_s.strip
        return owner unless owner.empty?
      end

      return "Unassigned" if touches.empty?

      counts = touches.group_by do |touch|
        owner = touch["owner"].to_s.strip
        owner.empty? ? "Unassigned" : owner
      end.transform_values(&:size)

      counts.max_by { |owner, count| [count, owner] }[0]
    end
  end
end
