module Vis

using RecursiveArrayTools
using ImageView, Gtk.ShortNames, Images
using ..Evo


function trace_video(evo::Evolution; key="fitness:1", color=colorant"green")
    trace = evo.trace[key]
    m = maximum.(trace) |> maximum
    normed = m > 0.0 ? trace ./ m : trace
    normed = (T -> (n -> isfinite(n) ? n : 0.0).(T)).(normed)
    frames = color .* normed
    fvec = VectorOfArray(frames)
    video = convert(Array, fvec)
    AxisArray(video)
end


function display_images(images; dims=(300,300), gui=nothing)
  rows, cols = size(images)
  show = ImageView.imshow!
  if gui ≡ nothing
    gui = imshow_gui(dims, (rows, cols))
    show = ImageView.imshow
  end
  canvases = gui["canvas"]
  
  for r in 1:rows
    for c in 1:cols
      i = r*c
      image = images[r,c]
      if image !== nothing
        show(canvases[r,c], images[r,c])
      end
    end
  end

  Gtk.showall(gui["window"])
  gui
end

end # module
