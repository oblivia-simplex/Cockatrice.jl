module Cockatrice

_VERSION = 0.01

include("Names.jl")
include("Config.jl")
include("Geo.jl")
include("Evo.jl")
include("Cosmos.jl")
include("examples/LinearGP.jl")

if "COCKATRICE_VIS" ∈ keys(ENV) && ENV["COCKATRICE_VIS"] == 1
    include("Vis.jl")
end


end # module
 
