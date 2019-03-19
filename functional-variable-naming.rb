# 2017-12-04
#
# Blog-images DO-NOT rely on Paperclip. This change was made months ago.
#
# The original implementation relied on Paperclip, but the 2nd-iteration
# handles things manually.
#
# Why the variable-naming schema?
#
# This controller-action is hyper-focused on doing 1 thing: committing images
# from HTTP-POST to disk and the database.
#
# Note there are 23 variables.
#
# Imagine trying to come up with 23 *meaningful names*.
#
# Instead, the code is written, IMO, such that each variable is easily
# understood by what has been assigned to it.
#
# Also, I do-not mutate these variables once created; this code is "functional".
#
# In this way, each variable is only ever 1 thing, and whenever you see
# a variable in this action, you know what it is.
#
# Finally, v23 is the data-structure expected by the VueJS front-end.
#
def post_commit_image
  v1  = params[:blog_post][:initiated_at]

  v2  = %{
    insert into blog_post
      (initiated_at)
    values
      ($1)
    on conflict
      do nothing
    returning
      initiated_at::text
    ;
  }

  V3::U.qq(v2, [v1])

  v3  = v1.parameterize
  v4  = params[:blog_post][:attachment]
  v5  = v4.path
  v6  = v4.original_filename
  v7  = File.extname(v6).downcase
  v8  = File.basename(v6, v7)
  v9  = v8.parameterize + v7
  v10 = Rails.root.join('..', '..', 'shared', 'public', 'blog-post-images', v3, 'sources')
  v11 = Rails.root.join('..', '..', 'shared', 'public', 'blog-post-images', v3, 'thumbnails')
  v12 = v10.join(v9)
  v13 = v11.join(v9)

  FileUtils.mkdir_p(v10)
  FileUtils.mkdir_p(v11)
  FileUtils.mv(v5, v12)

  File.chmod(0744, v12)

  # Always create a thumbnail 128x128px wide, for use with the admin UI.
  #
  `convert #{v12} -resize 128x128! #{v13}`

  v14 = Pathname.new('/blog-post-images/' + v3 + '/sources/' + v9)
  v15 = Pathname.new('/blog-post-images/' + v3 + '/thumbnails/' + v9)
  v16 = `identify -format "%wx%h" #{v12}`
  v17 = v16.split('x')
  v18 = `identify -format "%wx%h" #{v13}`
  v19 = v18.split('x')
  v20 = File.size(v12)
  v21 = File.size(v13)

  v22 = %{
    insert into blog_post_image
      (initiated_at, file_name, type, path, src, width, height, bytes, cover)
    values
      ($1, $2, $3, $4, $5, $6, $7, $8, default)
    ;
  }

  V3::U.qq(v22, [v1, v9, 'source',    v12, v14, v17[0], v17[1], v20])
  V3::U.qq(v22, [v1, v9, 'thumbnail', v13, v15, v19[0], v19[1], v21])

  v23 = {
    file_name: v9,
    images: {
      "#{v9}": [
        [v14.to_s, 'source', v17[0], v17[1]],
        [v15.to_s, 'thumbnail', 128, 128]
      ]
    },
    dimensions: {
      "#{v9}": {
        source_width:  v17[0],
        source_height: v17[1],
        custom_width:  nil,
        custom_height: nil
      }
    },
    thumbnails: {
      "#{v9}": v15.to_s
    },
    selected_image_dims: {
      "#{v9}": "#{v17[0]}x#{v17[1]}"
    },
    image_links: {
      "#{v9}": {
        "#{v17[0]}x#{v17[1]}": {
          a: v14.to_s,
          b: %{<a href="#{v14.to_s}"><img src="#{v14.to_s}" /></a>}
        },
        "#{v19[0]}x#{v19[1]}": {
          a: v15.to_s,
          b: %{<a href="#{v14.to_s}"><img src="#{v15.to_s}" /></a>}
        }
      }
    }
  }

  render(json: v23.to_json)
end
