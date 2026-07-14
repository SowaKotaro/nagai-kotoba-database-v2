-- =====================================================================
-- 長い日本語単語 収集・解析アプリ  スキーマ定義 (MySQL / InnoDB / utf8mb4)
--   - 想定規模: 1万レコード程度
--   - word : word_sense = 1 : 多 (同音異義語対応)
--   - genre は隣接リストで大→中→小の3階層を表現
--   - linguistic_feature は多対多
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- マスタ: ジャンル (大分類=level1 / 中分類=level2 / 小分類=level3)
--   parent_id を辿ることで「小が決まれば中・大も一意」を構造的に保証
-- ---------------------------------------------------------------------
CREATE TABLE genres (
  id         BIGINT       NOT NULL AUTO_INCREMENT,
  parent_id  BIGINT       NULL,
  level      TINYINT      NOT NULL COMMENT '1=大分類, 2=中分類, 3=小分類',
  name       VARCHAR(255) NOT NULL,
  created_at DATETIME(6)  NOT NULL,
  updated_at DATETIME(6)  NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_genres_parent_name (parent_id, name),
  KEY idx_genres_level (level),
  CONSTRAINT fk_genres_parent FOREIGN KEY (parent_id) REFERENCES genres (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------
-- マスタ: エンティティタイプ (人名 / 書籍名 など)
-- ---------------------------------------------------------------------
CREATE TABLE entity_types (
  id         BIGINT       NOT NULL AUTO_INCREMENT,
  name       VARCHAR(255) NOT NULL,
  created_at DATETIME(6)  NOT NULL,
  updated_at DATETIME(6)  NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_entity_types_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------
-- マスタ: 品詞
-- ---------------------------------------------------------------------
CREATE TABLE parts_of_speech (
  id         BIGINT       NOT NULL AUTO_INCREMENT,
  name       VARCHAR(255) NOT NULL,
  created_at DATETIME(6)  NOT NULL,
  updated_at DATETIME(6)  NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_parts_of_speech_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------
-- マスタ: 言語学的特徴 (連濁 / 重箱読み / 湯桶読み など) ※1語義に複数付与可
-- ---------------------------------------------------------------------
CREATE TABLE linguistic_features (
  id         BIGINT       NOT NULL AUTO_INCREMENT,
  name       VARCHAR(255) NOT NULL,
  created_at DATETIME(6)  NOT NULL,
  updated_at DATETIME(6)  NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_linguistic_features_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------
-- マスタ: 語種 (和語 / 漢語 / 英語 / フランス語 …)
--   「外来語」で束ねず言語ごとに切り分ける。値が増える開いた集合。
-- ---------------------------------------------------------------------
CREATE TABLE word_origins (
  id         BIGINT       NOT NULL AUTO_INCREMENT,
  name       VARCHAR(255) NOT NULL,
  created_at DATETIME(6)  NOT NULL,
  updated_at DATETIME(6)  NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_word_origins_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------
-- 単語 (表層形) : surface に紐づく属性のみを保持
--   char_type_pattern は surface から Ruby 側で生成 (漢/あ/ア/A/@ へ変換)
--   surface は清音・濁音・半濁音を検索で区別するため utf8mb4_0900_as_ci
--   (アクセント区別・大文字小文字非区別。ひらがな⇔カタカナ、A⇔a は同一視のまま)
-- ---------------------------------------------------------------------
CREATE TABLE words (
  id                BIGINT       NOT NULL AUTO_INCREMENT,
  surface           VARCHAR(768) NOT NULL COLLATE utf8mb4_0900_as_ci COMMENT '表層形 例: ABC殺人事件',
  char_type_pattern VARCHAR(768) NOT NULL COMMENT '文字タイプ列 例: AAA漢漢漢漢',
  created_at        DATETIME(6)  NOT NULL,
  updated_at        DATETIME(6)  NOT NULL,
  PRIMARY KEY (id),
  -- utf8mb4 のインデックスキー長制限(3072byte)対策で先頭191文字を一意キーに
  UNIQUE KEY uq_words_surface (surface(191)),
  KEY idx_words_char_type_pattern (char_type_pattern(191))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------
-- 語義 : 読み単位の情報。homonym 対応で word に対し 1:多
--   genre_id は末端(小分類)を指す
--   reading_length / first_char は読みからの派生 = 生成カラム(STORED)
--     ※ CHAR_LENGTH なので「きゃ」= 2 文字としてカウントされる
--   rhythm_pattern (ローマ字) は SQL で生成不可のため Ruby 側で設定
--   last_char も読みからの派生だが、末尾の長音符「ー」を飛ばして直前の文字を
--   取る必要があり、生成式にマルチバイト文字を含めると ActiveRecord の
--   SchemaDumper(MySQL2 アダプタ)が schema.rb をダンプする際に文字化けする
--   既知の制限があるため、生成カラムにはせず Ruby 側(LastChar)で設定する
--   reading / first_char / last_char は清音・濁音・半濁音を検索で区別するため
--   utf8mb4_0900_as_ci(生成カラムの照合順序は表の既定に従うため明示する)
-- ---------------------------------------------------------------------
CREATE TABLE word_senses (
  id                BIGINT        NOT NULL AUTO_INCREMENT,
  word_id           BIGINT        NOT NULL,
  genre_id          BIGINT        NULL COMMENT '小分類(末端)を指す',
  entity_type_id    BIGINT        NULL,
  part_of_speech_id BIGINT        NULL,
  reading           VARCHAR(768)  NOT NULL COLLATE utf8mb4_0900_as_ci COMMENT '読み',
  rhythm_pattern    VARCHAR(2048) NULL COMMENT '韻パターン(読みのローマ字表記)',
  mora_count        INT           NULL COMMENT 'モーラ数(拗音は1拍。Ruby 側で生成)',
  vowel_pattern     VARCHAR(1024) NULL COMMENT '母音パターン(rhythm_pattern から母音抽出。Ruby 側で生成)',
  meaning           TEXT          NULL COMMENT '意味',
  reading_length    INT           AS (CHAR_LENGTH(reading)) STORED COMMENT '読みの文字数',
  first_char        VARCHAR(8)    COLLATE utf8mb4_0900_as_ci AS (LEFT(reading, 1)) STORED COMMENT '先頭文字',
  last_char         VARCHAR(8)    NULL COLLATE utf8mb4_0900_as_ci COMMENT '末尾文字(末尾の長音「ー」は除く。Ruby 側で生成)',
  created_at        DATETIME(6)   NOT NULL,
  updated_at        DATETIME(6)   NOT NULL,
  PRIMARY KEY (id),
  KEY idx_word_senses_word           (word_id),
  KEY idx_word_senses_genre          (genre_id),
  KEY idx_word_senses_entity_type    (entity_type_id),
  KEY idx_word_senses_part_of_speech (part_of_speech_id),
  KEY idx_word_senses_reading        (reading(191)),
  KEY idx_word_senses_reading_length (reading_length),
  KEY idx_word_senses_first_char     (first_char),
  KEY idx_word_senses_last_char      (last_char),
  KEY idx_word_senses_mora_count     (mora_count),
  KEY idx_word_senses_vowel_pattern  (vowel_pattern(191)),
  CONSTRAINT fk_word_senses_word
    FOREIGN KEY (word_id)           REFERENCES words (id),
  CONSTRAINT fk_word_senses_genre
    FOREIGN KEY (genre_id)          REFERENCES genres (id),
  CONSTRAINT fk_word_senses_entity_type
    FOREIGN KEY (entity_type_id)    REFERENCES entity_types (id),
  CONSTRAINT fk_word_senses_part_of_speech
    FOREIGN KEY (part_of_speech_id) REFERENCES parts_of_speech (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------
-- 中間: 語義 × 言語学的特徴 (多対多)
--   特徴は単語の「該当部分」ごとに付与する。
--   例:「硫黄島からの手紙(イオウジマカラノテガミ)」に対し
--       連濁:硫黄島(イオウジマ) / 熟字訓:硫黄(イオウ) / 連濁:手紙(テガミ)。
--   このため同じ (word_sense, feature) でも target が異なれば複数行を許す。
--   target      … 表層形(word.surface)の部分文字列
--   target_reading … 語義の読み(word_senses.reading)の部分文字列
-- ---------------------------------------------------------------------
CREATE TABLE word_sense_features (
  id                    BIGINT       NOT NULL AUTO_INCREMENT,
  word_sense_id         BIGINT       NOT NULL,
  linguistic_feature_id BIGINT       NOT NULL,
  target                VARCHAR(768) NOT NULL COMMENT '該当部分(表層形の一部) 例: 硫黄島',
  target_reading        VARCHAR(768) NOT NULL COMMENT '該当部分の読み 例: イオウジマ',
  created_at            DATETIME(6)  NOT NULL,
  updated_at            DATETIME(6)  NOT NULL,
  PRIMARY KEY (id),
  -- (word_sense, feature, target) の三つ組で一意。target は prefix index(191文字)。
  UNIQUE KEY uq_wsf_sense_feature_target (word_sense_id, linguistic_feature_id, target(191)),
  KEY idx_wsf_feature (linguistic_feature_id),
  CONSTRAINT fk_wsf_word_sense
    FOREIGN KEY (word_sense_id)         REFERENCES word_senses (id),
  CONSTRAINT fk_wsf_linguistic_feature
    FOREIGN KEY (linguistic_feature_id) REFERENCES linguistic_features (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------
-- 中間: 語義 × 語種 (多対多)
--   混種語 (例: 歯ブラシ = 和語 + 英語) を表現するため 1 語義に複数の語種を許す。
-- ---------------------------------------------------------------------
CREATE TABLE word_sense_origins (
  id             BIGINT      NOT NULL AUTO_INCREMENT,
  word_sense_id  BIGINT      NOT NULL,
  word_origin_id BIGINT      NOT NULL,
  created_at     DATETIME(6) NOT NULL,
  updated_at     DATETIME(6) NOT NULL,
  PRIMARY KEY (id),
  -- (word_sense, origin) の二つ組で一意 (同じ語義に同じ語種を二重登録させない)。
  UNIQUE KEY uq_wso_sense_origin (word_sense_id, word_origin_id),
  KEY idx_wso_origin (word_origin_id),
  CONSTRAINT fk_wso_word_sense
    FOREIGN KEY (word_sense_id)  REFERENCES word_senses (id),
  CONSTRAINT fk_wso_word_origin
    FOREIGN KEY (word_origin_id) REFERENCES word_origins (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------
-- 別表記 : 語義 (word_sense) に 1:多。その語義にだけ付く別の表記。
--   例:「バタフライエフェクト」の自然科学の語義に別表記「バタフライ効果」。
--   読みも変わりうるため reading も保持する (バタフライエフェクト→バタフライこうか)。
-- ---------------------------------------------------------------------
CREATE TABLE word_sense_variants (
  id            BIGINT       NOT NULL AUTO_INCREMENT,
  word_sense_id BIGINT       NOT NULL,
  surface       VARCHAR(768) NOT NULL COMMENT '別表記の表層形 例: バタフライ効果',
  reading       VARCHAR(768) NULL     COMMENT '別表記の読み(変わる場合) 例: バタフライこうか',
  note          VARCHAR(255) NULL     COMMENT '任意メモ(旧字/略式 など)',
  created_at    DATETIME(6)  NOT NULL,
  updated_at    DATETIME(6)  NOT NULL,
  PRIMARY KEY (id),
  -- (word_sense, surface) で一意。surface は prefix index(191文字)。
  UNIQUE KEY uq_wsv_sense_surface (word_sense_id, surface(191)),
  CONSTRAINT fk_wsv_word_sense
    FOREIGN KEY (word_sense_id) REFERENCES word_senses (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
