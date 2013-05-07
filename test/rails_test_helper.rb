# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require 'rails'
require 'test_helper'

require File.expand_path("../dummy/config/environment.rb",  __FILE__)
require "rails/test_help"

require 'database_cleaner'

Rails.backtrace_cleaner.remove_silencers!

module TransactionalTests
  def run(runner)
    test_result = nil
    ActiveRecord::Base.transaction { test_result = super; raise ActiveRecord::Rollback }
    test_result
  end
end
