module Logging

using CSV
using Dates
using DataFrames
using StatsBase
using Printf
using Mmap
using ..Names

export Logger, log!, dump, log_ims


function make_stats_table(loggers)
    cols = [Symbol("$(lg.key)_$(nameof(lg.reducer))") for lg in loggers]
    cols = [:iteration_mean; cols]
    DataFrame([c => [] for c in cols]...)
end


function make_log_dir(name=Names.rand_name(2))
    stem = "log"
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
    table::DataFrame
    log_dir::String
    csv_name::String
    name::String
end


function Logger(loggers, name=Names.rand_name(2))
    n = now()
    name = @sprintf "%s.%02d-%02d" name hour(n) minute(n)
    csv_file = "report.csv"
    Logger(make_stats_table(loggers), make_log_dir(name), csv_file, name)
end

function log!(L::Logger, row)
    records = size(L.table, 1)
    append = records > 0
    push!(L.table, row)
    CSV.write("$(L.log_dir)/$(L.csv_name)", [L.table[end, :]], writeheader=!append, append=append)
    return records
end


function dump(L, obj)
    Serialization.serialize(make_dump_path(L), obj)
end


function log_ims(L::Logger, ims, step)
    dir = "$(L.log_dir)/IM/"
    mkpath(dir)
    for (i, im) in enumerate(ims)
        path = @sprintf "%s/%02d_IM_%04d.bin" dir i step
        m, n = UInt16.(size(im))
        open(path, "w+") do f
            write(f, m)
            write(f, n)
            write(f, im)
        end
    end
end


function read_im(path)
    open(path) do f
        m = read(f, UInt16)
        n = read(f, UInt16)
        Mmap.mmap(f, BitArray, (m, n)) |> deepcopy
    end
end


end
