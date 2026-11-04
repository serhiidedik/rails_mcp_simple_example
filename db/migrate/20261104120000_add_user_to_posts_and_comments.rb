class AddUserToPostsAndComments < ActiveRecord::Migration[8.1]
  def up
    add_reference :posts, :user, foreign_key: true
    add_reference :comments, :user, foreign_key: true

    # Existing records go to the first user. With records but no users, the last two lines fail
    # loudly: create a user first.
    execute "UPDATE posts SET user_id = (SELECT MIN(id) FROM users)"
    execute "UPDATE comments SET user_id = (SELECT MIN(id) FROM users)"

    change_column_null :posts, :user_id, false
    change_column_null :comments, :user_id, false
  end

  def down
    remove_reference :comments, :user
    remove_reference :posts, :user
  end
end
