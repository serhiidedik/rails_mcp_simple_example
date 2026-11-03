module Posts
  class Destroy < ApplicationInteraction
    integer :id

    def execute
      Post.find(id).destroy!
    end
  end
end
