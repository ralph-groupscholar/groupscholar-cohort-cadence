# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "json"
require "date"

require_relative "../lib/cadence_store"

module CadenceTestHelper
  def with_store
    Dir.mktmpdir do |dir|
      path = File.join(dir, "cadence.json")
      store = GroupScholar::CadenceStore.new(path)
      store.init_store
      yield store
    end
  end
end
