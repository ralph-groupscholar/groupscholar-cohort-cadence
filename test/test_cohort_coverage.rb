# frozen_string_literal: true

require_relative "test_helper"

class TestCohortCoverage < Minitest::Test
  include CadenceTestHelper

  def test_cohort_coverage_rolls_up_weekly_gaps
    with_store do |store|
      alpha = store.add_cohort(
        "name" => "Alpha Cohort",
        "start_date" => "2026-02-01",
        "end_date" => "2026-05-01",
        "size" => "20",
        "notes" => "STEM cohort"
      )
      beta = store.add_cohort(
        "name" => "Beta Cohort",
        "start_date" => "2026-02-01",
        "end_date" => "2026-05-01",
        "size" => "18",
        "notes" => "Arts cohort"
      )

      store.add_touchpoint(
        "cohort" => alpha["id"],
        "title" => "Kickoff",
        "date" => (Date.today + 1).iso8601,
        "owner" => "Program Lead",
        "channel" => "Zoom",
        "notes" => "Intro session"
      )
      store.add_touchpoint(
        "cohort" => alpha["id"],
        "title" => "Check-in",
        "date" => (Date.today + 10).iso8601,
        "owner" => "Program Lead",
        "channel" => "Zoom",
        "notes" => "Week 2 check-in"
      )

      report = store.cohort_coverage(4)
      alpha_entry = report["entries"].find { |entry| entry["cohort"]["id"] == alpha["id"] }
      beta_entry = report["entries"].find { |entry| entry["cohort"]["id"] == beta["id"] }

      assert_equal 4, alpha_entry["weeks_tracked"]
      assert_equal 2, alpha_entry["weeks_with_touchpoints"]
      assert_equal 2, alpha_entry["weeks_without_touchpoints"]
      assert_in_delta 0.5, alpha_entry["coverage_rate"], 0.001

      assert_equal 4, beta_entry["weeks_tracked"]
      assert_equal 0, beta_entry["weeks_with_touchpoints"]
      assert_equal 4, beta_entry["longest_gap_weeks"]
    end
  end

  def test_cohort_coverage_filters_by_cohort
    with_store do |store|
      alpha = store.add_cohort(
        "name" => "Alpha Cohort",
        "start_date" => "2026-02-01",
        "end_date" => "2026-05-01",
        "size" => "20",
        "notes" => "STEM cohort"
      )
      store.add_cohort(
        "name" => "Beta Cohort",
        "start_date" => "2026-02-01",
        "end_date" => "2026-05-01",
        "size" => "18",
        "notes" => "Arts cohort"
      )

      report = store.cohort_coverage(6, "Alpha Cohort")
      assert_equal 1, report["entries"].size
      assert_equal alpha["id"], report["entries"][0]["cohort"]["id"]
    end
  end
end
