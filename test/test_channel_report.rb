# frozen_string_literal: true

require_relative "test_helper"

class ChannelReportTest < Minitest::Test
  include CadenceTestHelper

  def test_channel_report_groups_channels_and_windows
    with_store do |store|
      data = store.load_store
      data["cohorts"] = [
        build_cohort("cohort-1", "Alpha Fellows"),
        build_cohort("cohort-2", "Beta Fellows")
      ]
      data["touchpoints"] = [
        build_touchpoint("cohort-1", "Alpha Fellows", "2026-02-05", "Lead A", "Zoom"),
        build_touchpoint("cohort-1", "Alpha Fellows", "2026-02-16", "Lead A", "Email"),
        build_touchpoint("cohort-2", "Beta Fellows", "2026-02-20", "Lead B", "Email"),
        build_touchpoint("cohort-2", "Beta Fellows", "2026-02-12", "Lead B", ""),
        build_touchpoint("cohort-1", "Alpha Fellows", "2026-01-20", "Lead A", "Zoom")
      ]
      store.save_store(data)

      Date.stub(:today, Date.new(2026, 2, 15)) do
        report = store.channel_report(14, 14)
        assert_equal 4, report["total_touchpoints"]

        email = report["channels"].find { |entry| entry["channel"] == "Email" }
        zoom = report["channels"].find { |entry| entry["channel"] == "Zoom" }
        unspecified = report["channels"].find { |entry| entry["channel"] == "Unspecified" }

        assert_equal 2, email["count"]
        assert_equal 0, email["past_count"]
        assert_equal 2, email["upcoming_count"]
        assert_equal "2026-02-16", email["next_touchpoint"]["date"]

        assert_equal 1, zoom["count"]
        assert_equal 1, zoom["past_count"]
        assert_equal 0, zoom["upcoming_count"]
        assert_equal "2026-02-05", zoom["last_touchpoint"]["date"]

        assert_equal 1, unspecified["count"]
      end
    end
  end

  def test_channel_report_owner_filter
    with_store do |store|
      data = store.load_store
      data["cohorts"] = [build_cohort("cohort-1", "Alpha Fellows")]
      data["touchpoints"] = [
        build_touchpoint("cohort-1", "Alpha Fellows", "2026-02-05", "Lead A", "Zoom"),
        build_touchpoint("cohort-1", "Alpha Fellows", "2026-02-16", "Lead B", "Email")
      ]
      store.save_store(data)

      Date.stub(:today, Date.new(2026, 2, 15)) do
        report = store.channel_report(14, 14, "Lead A")
        assert_equal 1, report["total_touchpoints"]
        assert_equal "Lead A", report["owner_filter"]
        assert_equal 1, report["channels"].size
        assert_equal "Zoom", report["channels"].first["channel"]
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
