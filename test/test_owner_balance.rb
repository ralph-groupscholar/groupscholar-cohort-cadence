# frozen_string_literal: true

require_relative "test_helper"

class OwnerBalanceTest < Minitest::Test
  include CadenceTestHelper

  def test_owner_balance_flags_over_and_under_loaded
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
        build_touchpoint("2026-02-03", "Owner A"),
        build_touchpoint("2026-02-04", "Owner A"),
        build_touchpoint("2026-02-05", "Owner A"),
        build_touchpoint("2026-02-06", "Owner A"),
        build_touchpoint("2026-02-07", "Owner B"),
        build_touchpoint("2026-02-08", "Owner B"),
        build_touchpoint("2026-02-09", "Owner B"),
        build_touchpoint("2026-02-10", "Owner C")
      ]
      store.save_store(data)

      Date.stub(:today, Date.new(2026, 2, 1)) do
        report = store.owner_balance(14, 0.25)
        assert_equal 8, report["total_touchpoints"]
        assert_equal 3, report["owners_count"]
        assert_equal 2.67, report["avg_per_owner"]

        owner_a = report["owners"].find { |entry| entry["owner"] == "Owner A" }
        owner_b = report["owners"].find { |entry| entry["owner"] == "Owner B" }
        owner_c = report["owners"].find { |entry| entry["owner"] == "Owner C" }

        assert_equal "overloaded", owner_a["status"]
        assert_equal "balanced", owner_b["status"]
        assert_equal "underloaded", owner_c["status"]
      end
    end
  end

  private

  def build_touchpoint(date, owner)
    {
      "id" => "touch-#{date}-#{owner}",
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
