# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_02_093000) do
  create_table "admins", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["username"], name: "index_admins_on_username", unique: true
  end

  create_table "entity_types", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "uq_entity_types_name", unique: true
  end

  create_table "genres", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "level", limit: 1, null: false, comment: "1=大分類, 2=中分類, 3=小分類"
    t.string "name", null: false
    t.bigint "parent_id"
    t.datetime "updated_at", null: false
    t.index ["level"], name: "idx_genres_level"
    t.index ["parent_id", "name"], name: "uq_genres_parent_name", unique: true
    t.index ["parent_id"], name: "index_genres_on_parent_id"
  end

  create_table "linguistic_features", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "uq_linguistic_features_name", unique: true
  end

  create_table "parts_of_speech", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "uq_parts_of_speech_name", unique: true
  end

  create_table "sessions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "admin_id", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["admin_id"], name: "index_sessions_on_admin_id"
  end

  create_table "word_senses", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "entity_type_id"
    t.virtual "first_char", type: :string, limit: 8, comment: "先頭文字", as: "left(`reading`,1)", stored: true
    t.bigint "genre_id", comment: "小分類(末端)を指す"
    t.virtual "last_char", type: :string, limit: 8, comment: "末尾文字", as: "right(`reading`,1)", stored: true
    t.text "meaning", comment: "意味"
    t.bigint "part_of_speech_id"
    t.string "reading", limit: 768, null: false, comment: "読み"
    t.virtual "reading_length", type: :integer, comment: "読みの文字数", as: "char_length(`reading`)", stored: true
    t.string "rhythm_pattern", limit: 2048, comment: "韻パターン(読みのローマ字表記)"
    t.datetime "updated_at", null: false
    t.bigint "word_id", null: false
    t.index ["entity_type_id"], name: "idx_word_senses_entity_type"
    t.index ["first_char"], name: "idx_word_senses_first_char"
    t.index ["genre_id"], name: "idx_word_senses_genre"
    t.index ["last_char"], name: "idx_word_senses_last_char"
    t.index ["part_of_speech_id"], name: "idx_word_senses_part_of_speech"
    t.index ["reading"], name: "idx_word_senses_reading", length: 191
    t.index ["reading_length"], name: "idx_word_senses_reading_length"
    t.index ["word_id"], name: "idx_word_senses_word"
  end

  create_table "words", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "char_type_pattern", limit: 768, null: false, comment: "文字タイプ列 例: AAA漢漢漢漢"
    t.datetime "created_at", null: false
    t.string "surface", limit: 768, null: false, comment: "表層形 例: ABC殺人事件"
    t.datetime "updated_at", null: false
    t.index ["char_type_pattern"], name: "idx_words_char_type_pattern", length: 191
    t.index ["surface"], name: "uq_words_surface", unique: true, length: 191
  end

  add_foreign_key "genres", "genres", column: "parent_id"
  add_foreign_key "sessions", "admins"
  add_foreign_key "word_senses", "entity_types", name: "fk_word_senses_entity_type"
  add_foreign_key "word_senses", "genres", name: "fk_word_senses_genre"
  add_foreign_key "word_senses", "parts_of_speech", name: "fk_word_senses_part_of_speech"
  add_foreign_key "word_senses", "words", name: "fk_word_senses_word"
end
