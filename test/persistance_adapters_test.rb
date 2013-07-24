require_relative 'test_helper'
require 'fileutils'

module PersistenceAdapterTest
  def storage
    raise NotImplementedError
  end

  def test_save_execution_plan
    plan = { id: 1, 'value' => 2 }
    -> { storage.load_execution_plan(1) }.must_raise KeyError

    storage.save_execution_plan(1, plan)
    storage.load_execution_plan(1)[:id].must_equal 1
    storage.load_execution_plan(1)['value'].must_equal 2
    storage.load_execution_plan(1).keys.size.must_equal 2

    storage.save_execution_plan(1, nil)
    -> { storage.load_execution_plan(1) }.must_raise KeyError
  end

  def test_save_action
    action = { id: 1, 'value' => 2 }
    -> { storage.load_action(1, 1) }.must_raise KeyError

    storage.save_action(1, 1, action)
    storage.load_action(1, 1)[:id].must_equal 1
    storage.load_action(1, 1)['value'].must_equal 2
    storage.load_action(1, 1).keys.size.must_equal 2

    storage.save_action(1, 1, nil)
    -> { storage.load_action(1, 1) }.must_raise KeyError
  end
end

class MemoryTest < MiniTest::Unit::TestCase
  include PersistenceAdapterTest

  def storage
    @storage ||= Dynflow::PersistenceAdapters::Memory.new
  end
end

class SimpleFileStorageTest < MiniTest::Unit::TestCase
  include PersistenceAdapterTest

  def storage_path
    "#{File.dirname(__FILE__)}/simple_file_storage"
  end

  def setup
    Dir.mkdir storage_path
  end

  def storage
    @storage ||= begin
      Dynflow::PersistenceAdapters::SimpleFileStorage.new storage_path
    end
  end

  def teardown
    FileUtils.rm_rf storage_path
  end
end


