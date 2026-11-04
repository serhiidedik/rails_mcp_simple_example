class CreateComments < ActiveRecord::Migration[8.1]
  def change
    create_table :comments do |t|
      # The composite index below serves both this foreign key and keyset pagination within a post.
      t.references :post, null: false, foreign_key: true, index: false
      t.text :body, null: false

      t.timestamps
    end

    add_index :comments, [ :post_id, :id ]
  end
end
