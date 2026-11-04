# For operations that change a record: only its owner may. Include it, then do the write inside
# `change(record) { ... }`.
module OwnerOnly
  extend ActiveSupport::Concern

  class NotOwner < StandardError
    attr_reader :record

    def initialize(record)
      @record = record
      super("#{record.class.name} #{record.id} belongs to another user")
    end
  end

  included do
    object :actor, class: Actor
  end

  private

  # The lock closes the gap between reading a record and writing it. If someone deleted the row
  # in that gap, this raises RecordNotFound, rather than reporting a write that changed nothing.
  # While a post is being deleted, the database holds back new comments on it, until it can
  # refuse them with a foreign key error (see Comments::Create).
  def change(record)
    raise NotOwner.new(record) unless actor.may_change?(record)

    record.with_lock { yield record }
  rescue ActiveRecord::RecordNotFound => error
    # Reloading the row for the lock raises without the id, which the caller needs to say what is gone.
    raise ActiveRecord::RecordNotFound.new(error.message, record.class.name, record.class.primary_key, record.id)
  end
end
