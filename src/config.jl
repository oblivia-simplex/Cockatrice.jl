module Config

using YAML
using Dates
include("Names.jl")

export get_config

"convert Dict to named tuple"
function proc_config(cfg::Dict)
    (; (Symbol(k)=>proc_config(v) for (k, v) in cfg)...)
end

proc_config(v) = v

"combine YAML file and kwargs, make sure ID is specified"
function parse(cfg_file::String; kwargs...)
    cfg = YAML.load_file(cfg_file)
    for (k, v) in kwargs
        cfg[String(k)] = v
    end
    # generate id, use date if no existing id
    if ~(:id in keys(cfg))
      cfg["id"] = "$(Names.rand_name(2))_$(Dates.now())"
    end
    proc_config(cfg)
end

end # end module
