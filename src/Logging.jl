module Logging

using CSV
using Dates
using Serialization
using DataFrames
using StatsBase
using Printf
using Mmap
using Plots
using ..Names

export Logger, log!, dump, log_ims


function make_stats_table(loggers)
    cols = [Symbol("$(lg.key)_$(nameof(lg.reducer))") for lg in loggers]
    cols = [:iteration_mean; cols]
    Float64.(DataFrame([c => [] for c in cols]...))
end


function make_log_dir(name=Names.rand_name(2))
    stem = "$(ENV["HOME"])/logs/refusr/"
    mkpath(stem)
    n = now()
    dir = @sprintf "%s/%04d/%02d/%02d/%s" stem year(n) month(n) day(n) name
    mkpath(dir)
    return dir
end

function make_csv_filename(name=Names.rand_name(2))
    n = now()
    @sprintf "%s.%02d-%02d.csv" name hour(n) minute(n)
end


function make_dump_path(L)
    "$(L.log_dir)/$(L.name).dump"
end

struct Logger
    config::NamedTuple
    table::DataFrame
    im_log::Vector
    log_dir::String
    csv_name::String
    name::String
    specimens::Vector
    timing::Vector
end


function dump_logger(L::Logger)
    dump_path = "$(L.log_dir)/.L.dump"
    serialize(dump_path, L)
    return dump_path
end


function Logger(loggers, config)
    n = now()
    if :experiment ∈ keys(config)
        experiment = config.experiment
    else
        experiment = Names.rand_name(2)
    end
    name = @sprintf "%s.%02d-%02d" experiment hour(n) minute(n)
    csv_file = "report.csv"
    dir = make_log_dir(name)
    write("$(dir)/config.yaml", config.yaml)
    Logger(config, make_stats_table(loggers), [], dir, csv_file, name, [], [])
end

function log!(L::Logger, row)
    records = size(L.table, 1)
    append = records > 0
    push!(L.table, row)
    CSV.write("$(L.log_dir)/$(L.csv_name)", [L.table[end, :]], writeheader=!append, append=append)
    dump_path = dump_logger(L)
    @debug "Dumped logger" dump_path
    return records
end


function dump(L, obj)
    Serialization.serialize(make_dump_path(L), obj)
end


function write_im(path, im)
    m, n = UInt16.(size(im))
    open(path, "w+") do f
        write(f, m)
        write(f, n)
        write(f, im)
    end
end

function log_ims(L::Logger, ims, step)
    push!(L.im_log, ims)
    dir = "$(L.log_dir)/IM/"
    mkpath(dir)
    for (i, im) in enumerate(ims)
        path = @sprintf "%s/%02d_IM_%04d.bin" dir i step
        write_im(path, im)
    end
end


function read_im(path)
    open(path) do f
        m = read(f, UInt16)
        n = read(f, UInt16)
        buf = BitArray(undef, (m, n))
        read!(f, buf)
        buf
    end
end


function make_plots(L::Logger)
    
end

end
