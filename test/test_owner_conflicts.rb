# frozen_string_literal: true

require_relative "test_helper"

class OwnerConflictsTest < Minitest::Test
  include CadenceTestHelper

  def test_owner_conflicts_flags_days_over_daily_limit
    with_store do |store|
      data = store.load_store
      data["cohorts"] = [
        {
          "id" => "cohort-1",
          "name" => "Alpha Fellows",
          "start_date" => "2026-01-01",
          "end_date" => "2026-06-30",
          "size" => 20,
          "notes" => "Test cohort",
          "created_at" => "2026-01-01T00:00:00Z"
        }
      ]
      data["touchpoints"] = [
        build_touchpoint("2026-02-03", "Owner A", "touch-1"),
        build_touchpoint("2026-02-03", "Owner A", "touch-2"),
        build_touchpoint("2026-02-03", "Owner A", "touch-3"),
        build_touchpoint("2026-02-05", "Owner A", "touch-4"),
        build_touchpoint("2026-02-04", "Owner B", "touch-5"),
        build_touchpoint("2026-02-04", "Owner B", "touch-6")
      ]
      store.save_store(data)

      Date.stub(:today, Date.new(2026, 2, 1)) do
        report = store.owner_conflicts(7, 2)
        assert_equal 6, report["total_touchpoints"]
        assert_equal 1, report["owners_count"]
        assert_equal 1, report["conflict_days"]

        owner_a = report["owners"].find { |entry| entry["owner"] == "Owner A" }
        assert_equal 4, owner_a["total_touchpoints"]
        assert_equal 1, owner_a["conflict_days"]

        day = owner_a["days"].first
        assert_equal "2026-02-03", day["date"]
        assert_equal 3, day["count"]
      end
    end
  end

  private

  def build_touchpoint(date, owner, id)
    {
      "id" => id,
      "cohort_id" => "cohort-1",
      "cohort_name" => "Alpha Fellows",
      "title" => "Check-in",
      "date" => date,
      "owner" => owner,
      "channel" => "Zoom",
      "notes" => "Weekly sync",
      "created_at" => "2026-01-15T00:00:00Z"
    }
  end
end
