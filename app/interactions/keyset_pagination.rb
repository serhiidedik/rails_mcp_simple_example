# One page of a collection, newest first, using keyset pagination: stable under concurrent
# inserts, and its cost does not grow with the depth of the page. Include it, then return
# `paginate(scope)` from #execute.
module KeysetPagination
  extend ActiveSupport::Concern

  DEFAULT_LIMIT = 25
  MAX_LIMIT = 100
  MAX_ID = 2**63 - 1

  Page = Data.define(:records, :next_cursor)

  included do
    string :cursor, default: nil
    integer :limit, default: DEFAULT_LIMIT

    validates :limit, numericality: { greater_than: 0, less_than_or_equal_to: MAX_LIMIT }
    validate :cursor_is_well_formed
  end

  private

  def paginate(scope)
    scope = scope.reorder(id: :desc)
    scope = scope.where(id: ...decoded_cursor) if cursor
    rows = scope.limit(limit + 1).to_a
    records = rows.first(limit)

    Page.new(records:, next_cursor: rows.size > limit ? encode_cursor(records.last.id) : nil)
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
