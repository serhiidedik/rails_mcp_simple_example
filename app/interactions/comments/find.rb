module Comments
  class Find < ApplicationInteraction
    integer :id

    def execute
      Comment.find(id)
    end
  end
end
