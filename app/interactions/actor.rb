# Who is asking. An MCP tool builds this from the verified token, never from tool arguments.
class Actor < Data.define(:user_id)
  def owns?(record)
    record.user_id == user_id
  end

  def may_change?(record)
    owns?(record)
  end

  # REST has no sign-in in this sample, so nobody is identified there. Only server code can build this.
  class Unrestricted < Actor
    def may_change?(_record)
      true
    end
  end

  def self.unrestricted
    Unrestricted.new(user_id: nil)
  end
end
