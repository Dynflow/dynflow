# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 20130506185041) do

  create_table "dynflow_ar_persisted_plans", :force => true do |t|
    t.integer  "user_id"
    t.string   "status"
    t.datetime "created_at", :null => false
    t.datetime "updated_at", :null => false
  end

  add_index "dynflow_ar_persisted_plans", ["status"], :name => "index_dynflow_ar_persisted_plans_on_status"
  add_index "dynflow_ar_persisted_plans", ["user_id"], :name => "index_dynflow_ar_persisted_plans_on_user_id"

  create_table "dynflow_ar_persisted_steps", :force => true do |t|
    t.integer  "ar_persisted_plan_id"
    t.text     "data"
    t.string   "status"
    t.datetime "created_at",           :null => false
    t.datetime "updated_at",           :null => false
  end

  add_index "dynflow_ar_persisted_steps", ["ar_persisted_plan_id"], :name => "index_dynflow_ar_persisted_steps_on_ar_persisted_plan_id"
  add_index "dynflow_ar_persisted_steps", ["status"], :name => "index_dynflow_ar_persisted_steps_on_status"

  create_table "events", :force => true do |t|
    t.string   "name"
    t.datetime "created_at", :null => false
    t.datetime "updated_at", :null => false
  end

  create_table "guests", :force => true do |t|
    t.integer  "event_id"
    t.integer  "user_id"
    t.string   "invitation_status"
    t.datetime "created_at",        :null => false
    t.datetime "updated_at",        :null => false
  end

  add_index "guests", ["event_id"], :name => "index_guests_on_event_id"
  add_index "guests", ["user_id"], :name => "index_guests_on_user_id"

  create_table "logs", :force => true do |t|
    t.string   "text"
    t.datetime "created_at", :null => false
    t.datetime "updated_at", :null => false
  end

  create_table "users", :force => true do |t|
    t.string   "login"
    t.datetime "created_at", :null => false
    t.datetime "updated_at", :null => false
  end

end
