class Comment < ApplicationRecord
  BODY_MAX_LENGTH = 10_000

  belongs_to :post

  validates :body, presence: true, length: { maximum: BODY_MAX_LENGTH }
end
