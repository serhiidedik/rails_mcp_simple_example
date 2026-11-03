module Posts
  # One page of posts, newest first, using keyset pagination: stable under concurrent
  # inserts, and its cost does not grow with the depth of the page.
  class List < ApplicationInteraction
    DEFAULT_LIMIT = 25
    MAX_LIMIT = 100
    MAX_ID = 2**63 - 1

    Page = Data.define(:posts, :next_cursor)

    string :cursor, default: nil
    integer :limit, default: DEFAULT_LIMIT

    validates :limit, numericality: { greater_than: 0, less_than_or_equal_to: MAX_LIMIT }
    validate :cursor_is_well_formed

    def execute
      rows = scope.limit(limit + 1).to_a
      posts = rows.first(limit)

      Page.new(posts:, next_cursor: rows.size > limit ? encode_cursor(posts.last.id) : nil)
    end

    private

    def scope
      posts = Post.order(id: :desc)
      cursor ? posts.where(id: ...decoded_cursor) : posts
    end

    def cursor_is_well_formed
      errors.add(:cursor, :invalid) if cursor && decoded_cursor.nil?
    end

    # The cursor is opaque to clients. Tampering with it can only select another page
    # of a collection the caller may already read, so it is encoded, not signed.
    def encode_cursor(id)
      Base64.urlsafe_encode64(id.to_s, padding: false)
    end

    def decoded_cursor
      return @decoded_cursor if defined?(@decoded_cursor)

      @decoded_cursor = begin
        id = Integer(Base64.urlsafe_decode64(cursor), 10)
        id if id.between?(1, MAX_ID)
      rescue ArgumentError
        nil
      end
    end
  end
end
