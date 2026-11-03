require "test_helper"

class PostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @post = posts(:one)
  end

  test "should get index" do
    get posts_url, as: :json
    assert_response :success
  end

  test "should create post" do
    assert_difference("Post.count") do
      post posts_url, params: { post: { body: @post.body, published: @post.published, title: @post.title } }, as: :json
    end

    assert_response :created
  end

  test "should show post" do
    get post_url(@post), as: :json
    assert_response :success
  end

  test "should update post" do
    patch post_url(@post), params: { post: { body: @post.body, published: @post.published, title: @post.title } }, as: :json
    assert_response :success
  end

  test "should destroy post" do
    assert_difference("Post.count", -1) do
      delete post_url(@post), as: :json
    end

    assert_response :no_content
  end

  test "index paginates and links to the next page" do
    Post.delete_all
    created = Array.new(3) { |i| Post.create!(title: "Post #{i}") }

    get posts_url(limit: 2), as: :json
    assert_response :success
    assert_equal created.last(2).reverse.map(&:id), response.parsed_body.pluck("id")
    next_url = response.headers["Link"][/<(.+)>; rel="next"/, 1]
    assert next_url

    get next_url, as: :json
    assert_equal [ created.first.id ], response.parsed_body.pluck("id")
    assert_nil response.headers["Link"]
  end

  test "index rejects an invalid limit" do
    get posts_url(limit: 1000), as: :json
    assert_response :unprocessable_content
    assert response.parsed_body.key?("limit")
  end

  test "create returns validation errors" do
    assert_no_difference("Post.count") do
      post posts_url, params: { post: { title: "" } }, as: :json
    end

    assert_response :unprocessable_content
    assert_equal [ "can't be blank" ], response.parsed_body["title"]
  end

  test "update returns validation errors" do
    patch post_url(@post), params: { post: { title: "" } }, as: :json

    assert_response :unprocessable_content
    assert_equal [ "can't be blank" ], response.parsed_body["title"]
  end

  test "a missing or malformed id is a 404" do
    get post_url(id: 0), as: :json
    assert_response :not_found

    get "/posts/abc", as: :json
    assert_response :not_found
  end
end
