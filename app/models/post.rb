class Post < ApplicationRecord
  TITLE_MAX_LENGTH = 255
  BODY_MAX_LENGTH = 100_000

  validates :title, presence: true, length: { maximum: TITLE_MAX_LENGTH }
  validates :body, length: { maximum: BODY_MAX_LENGTH }
end
