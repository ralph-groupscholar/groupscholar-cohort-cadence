# frozen_string_literal: true

require_relative "test_helper"

class ActionPlanTest < Minitest::Test
  include CadenceTestHelper

  def test_action_plan_returns_recommended_touchpoints
    with_store do |store|
      data = store.load_store
      data["cohorts"] = [
        build_cohort("cohort-a", "Active Cohort", "2025-12-01", "2026-06-30"),
        build_cohort("cohort-b", "Needs Touchpoint", "2025-12-01", "2026-06-30"),
        build_cohort("cohort-c", "Upcoming Cohort", "2026-03-10", "2026-06-30")
      ]
      data["touchpoints"] = [
        build_touchpoint("cohort-a", "Active Cohort", "2026-01-15", "Program Lead"),
        build_touchpoint("cohort-a", "Active Cohort", "2026-02-20", "Program Lead"),
        build_touchpoint("cohort-b", "Needs Touchpoint", "2026-01-01", "Success Coach")
      ]
      store.save_store(data)

      Date.stub(:today, Date.new(2026, 2, 1)) do
        report = store.action_plan(21, 30)
        assert_equal 3, report["cohort_count"]
        assert_equal 2, report["action_count"]

        first = report["entries"][0]
        assert_equal "Needs Touchpoint", first["cohort"]["name"]
        assert_equal true, first["within_lookahead"]
        assert_equal "Success Coach", first["recommended_owner"]
        assert_equal "2026-02-01", first["recommended_date"]

        second = report["entries"][1]
        assert_equal "Upcoming Cohort", second["cohort"]["name"]
        assert_equal false, second["within_lookahead"]
        assert_equal "Unassigned", second["recommended_owner"]
        assert_equal "2026-03-10", second["recommended_date"]
      end
    end
  end

  private

  def build_cohort(id, name, start_date, end_date)
    {
      "id" => id,
      "name" => name,
      "start_date" => start_date,
      "end_date" => end_date,
      "size" => 20,
      "notes" => "Test cohort",
      "created_at" => "2025-12-01T00:00:00Z"
    }
  end

  def build_touchpoint(cohort_id, cohort_name, date, owner)
    {
      "id" => "touch-#{cohort_id}-#{date}",
      "cohort_id" => cohort_id,
      "cohort_name" => cohort_name,
      "title" => "Check-in",
      "date" => date,
      "owner" => owner,
      "channel" => "Zoom",
      "notes" => "Weekly sync",
      "created_at" => "2026-01-15T00:00:00Z"
    }
  end
end
