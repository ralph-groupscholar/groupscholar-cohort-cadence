# frozen_string_literal: true

require_relative "test_helper"

class WeekdayReportTest < Minitest::Test
  include CadenceTestHelper

  def test_weekday_report_groups_touchpoints_by_weekday
    with_store do |store|
      data = store.load_store
      data["cohorts"] = [build_cohort("cohort-1", "Alpha Fellows")]
      data["touchpoints"] = [
        build_touchpoint("cohort-1", "Alpha Fellows", "2026-02-09", "Lead A", "Zoom"),
        build_touchpoint("cohort-1", "Alpha Fellows", "2026-02-10", "Lead A", "Email"),
        build_touchpoint("cohort-1", "Alpha Fellows", "2026-02-16", "Lead B", "Email"),
        build_touchpoint("cohort-1", "Alpha Fellows", "2026-02-01", "Lead A", "Chat")
      ]
      store.save_store(data)

      Date.stub(:today, Date.new(2026, 2, 12)) do
        report = store.weekday_report(7, 7)
        assert_equal 3, report["total_touchpoints"]

        monday = report["weekdays"].find { |entry| entry["weekday"] == "Monday" }
        tuesday = report["weekdays"].find { |entry| entry["weekday"] == "Tuesday" }
        sunday = report["weekdays"].find { |entry| entry["weekday"] == "Sunday" }

        assert_equal 2, monday["count"]
        assert_equal 1, monday["upcoming_count"]
        assert_equal 1, monday["past_count"]

        assert_equal 1, tuesday["count"]
        assert_equal 1, tuesday["past_count"]
        assert_equal 0, tuesday["upcoming_count"]

        assert_equal 0, sunday["count"]
      end
    end
  end

  def test_weekday_report_owner_filter
    with_store do |store|
      data = store.load_store
      data["cohorts"] = [build_cohort("cohort-1", "Alpha Fellows")]
      data["touchpoints"] = [
        build_touchpoint("cohort-1", "Alpha Fellows", "2026-02-09", "Lead A", "Zoom"),
        build_touchpoint("cohort-1", "Alpha Fellows", "2026-02-10", "Lead B", "Email")
      ]
      store.save_store(data)

      Date.stub(:today, Date.new(2026, 2, 10)) do
        report = store.weekday_report(7, 7, "Lead A")
        assert_equal 1, report["total_touchpoints"]
        assert_equal "Lead A", report["owner_filter"]
        monday = report["weekdays"].find { |entry| entry["weekday"] == "Monday" }
        assert_equal 1, monday["count"]
      end
    end
  end

  private

  def build_cohort(id, name)
    {
      "id" => id,
      "name" => name,
      "start_date" => "2026-01-01",
      "end_date" => "2026-06-30",
      "size" => 20,
      "notes" => "Test cohort",
      "created_at" => "2026-01-01T00:00:00Z"
    }
  end

  def build_touchpoint(cohort_id, cohort_name, date, owner, channel)
    {
      "id" => "touch-#{cohort_id}-#{date}-#{owner}-#{channel}",
      "cohort_id" => cohort_id,
      "cohort_name" => cohort_name,
      "title" => "Check-in",
      "date" => date,
      "owner" => owner,
      "channel" => channel,
      "notes" => "Weekly sync",
      "created_at" => "2026-01-15T00:00:00Z"
    }
  end
end
