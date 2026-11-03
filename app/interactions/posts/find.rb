module Posts
  class Find < ApplicationInteraction
    integer :id

    def execute
      Post.find(id)
    end
  end
end
