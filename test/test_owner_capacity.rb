# frozen_string_literal: true

require_relative "test_helper"

class OwnerCapacityTest < Minitest::Test
  include CadenceTestHelper

  def test_owner_capacity_flags_over_limit_weeks
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
        build_touchpoint("2026-02-10", "Owner B"),
        build_touchpoint("2026-02-20", "Owner A")
      ]
      store.save_store(data)

      Date.stub(:today, Date.new(2026, 2, 1)) do
        report = store.owner_capacity(2, 2)
        assert_equal 4, report["total_touchpoints"]
        assert_equal 2, report["owners_count"]
        assert_equal 1, report["over_limit_weeks"]

        owner_a = report["owners"].find { |entry| entry["owner"] == "Owner A" }
        assert_equal 3, owner_a["total_touchpoints"]
        assert_equal 1, owner_a["over_limit_weeks"]

        week = owner_a["weeks"].find { |entry| entry["week_start"] == "2026-02-02" }
        assert_equal true, week["over_limit"]
        assert_equal 3, week["count"]
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
