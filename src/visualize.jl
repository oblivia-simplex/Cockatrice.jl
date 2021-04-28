using ImageView, Gtk.ShortNames, Images

function display_images(images; dims=(300,300))
  rows = 2
  cols = ceil(length(images)/2) |> Int
  gui = imshow_gui(dims, (rows, cols))
  canvases = gui["canvas"]
  
  for r in 1:rows
    for c in 1:cols
      i = r*c
      if i <= length(images)
        imshow(canvases[r,c], images[i])
      end
    end
  end

  Gtk.showall(gui["window"])
  gui
end
