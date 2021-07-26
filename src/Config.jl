module Config

using YAML
using Dates
using ..Names

export get_config, get_fitness_function

"convert Dict to named tuple"
function proc_config(cfg::Dict)
    (; (Symbol(k)=>proc_config(v) for (k, v) in cfg)...)
end

proc_config(v) = v

"combine YAML file and kwargs, make sure ID is specified"
function parse(cfg_file::String; kwargs...)
    cfg_txt = read(cfg_file, String)
    cfg = YAML.load_file(cfg_file)
    
    for (k, v) in kwargs
        cfg[String(k)] = v
    end
    cfg["yaml"] = cfg_txt
    # generate id, use date if no existing id
    if ~(:id in keys(cfg))
      cfg["id"] = "$(Names.rand_name(2))_$(Dates.now())"
    end
    proc_config(cfg)
end


function get_fitness_function(config::NamedTuple, mod)
    Meta.parse("$(mod).$(config.selection.fitness_function)") |> eval
end


function get_fitness_function(config_path::String, mod)
    get_fitness_function(Config.parse(config_path), mod)
end


end # end module
