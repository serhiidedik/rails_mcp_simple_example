module Comments
  class Destroy < ApplicationInteraction
    integer :id

    def execute
      Comment.find(id).destroy!
    end
  end
end
