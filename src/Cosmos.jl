module Cosmos

using Printf
using Distributed
using DistributedArrays
using StatsBase
using Dates
using DataFrames
using ..Evo
using ..Config


Evolution = Evo.Evolution
World = DArray{Evo.Evolution,1,Array{Evo.Evolution,1}}


function δ_step_for_duration!(E::World, duration::TimePeriod; kwargs...)
    futs = [@spawnat w Evo.step_for_duration!(E[:L][1], duration; kwargs...) for w in procs(E)]
    iters = asyncmap(fetch, futs)
    if rand() < 0.1
        extra = iters .- minimum(iters) |> sum
        @info "Iterations per $(duration): mean $(mean(iters)), min $(minimum(iters)), extra $(extra), total $(sum(iters))"
    end
    return
end


function δ_step!(E::World; kwargs...)
    if !(:step ∈ keys(kwargs))
        step = Evo.step!
    else
        step = kwargs.data.step
    end
    futs = [@spawnat w Evo.step!(E[:L][1]; kwargs...) for w in procs(E)]
    asyncmap(fetch, futs)
    return
end


DEFAULT_LOGGERS = [
    (key="fitness_1", reducer=StatsBase.mean),
]

function δ_stats(E::World; key="fitness_1", ϕ=mean)
    futs = [@spawnat w (filter(isfinite, E[:L][1].trace[key][end]) 
                        |> ϕ) for w in procs(E)]
    asyncmap(fetch, futs) |> ϕ
end

#=
function δ_stats(E::World; key="fitness_1", ϕ=mean)
    #fut = @spawnat 2 E[:L][1].trace2.d[key][2:end, E[:L][1].iteration, :, :]
    fut = @spawnat 2 Evo.slice(E[:L][1].trace2, key=key, iteration=E[:L][1].iteration)
    arr = fetch(fut)
    filter(isfinite, arr) |> ϕ
end
=#

function δ_init(;config=nothing,
                fitness::Function=(_) -> [rand()],
                crossover::Function,
                mutate::Function,
                creature_type::DataType,
                tracers=[],
                workers=workers())::DArray

    #trace = Evo.Trace(tracers, config.n_gen * 500, config.population.size)
    DArray((length(workers),), workers) do I
        [Evo.Evolution(config,
                       creature_type=creature_type,
                       fitness=fitness,
                       crossover=crossover,
                       mutate=mutate,
                       tracers=tracers)]
    end
end



function make_stats_table(loggers)
    cols = [Symbol("$(lg.key)_$(nameof(lg.reducer))") for lg in loggers]
    DataFrame([c => [] for c in cols]...)
end


function make_log_path(name=Names.rand_name(2))
    stem = "log"
    now = now()
    dir = @sprintf "%s/%04d/%02d/%02d/" stem year(now) month(now) day(now)
    mkpath(dir)
    file = @sprintf "%s.%02d-%02d.csv" name hour(now) minute(now)
    dir * file
end


struct Logger
    table::DataFrame
    csv_path::String
    name::String
end

function Logger(loggers::Vector{NamedTuple}, name=Names.rand_name(2))
    Loggers(make_stats_table(loggers), make_log_path(name), name)
end

function log!(L::Logger, row)
    records = size(L.table, 1)
    append = records > 0
    push!(L.table, row)
    CSV.write(L.csv_path, [L.table[end, :]], append=append)
    return records
end




function δ_run(;config::NamedTuple,
               fitness::Function,
               workers=workers(),
               tracers=[],
               loggers=[],
               mutate::Function,
               crossover::Function,
               creature_type::DataType,
               kwargs...)

    if :experiment ∈ keys(config)
        LOGGER = Logger(loggers, config.experiment)
    else
        LOGGER = Logger(loggers)
    end

    E = δ_init(config=config,
               fitness=fitness,
               workers=workers,
               creature_type=creature_type,
               tracers=tracers,
               crossover=crossover,
               mutate=mutate)

    for i in 1:config.n_gen
        #δ_step!(E; kwargs...)
        δ_step_for_duration!(E, Second(1); kwargs...)

        # Migration
        if rand() < config.population.migration_rate
            if config.population.migration_type == "elite"
                elite_migration!(E)
            elseif config.population.migration_type == "swap"
                swap_migration!(E)
            end
        end

        # Logging
        if i % config.logging.log_every != 0
            continue
        end

        s = []
        for logger in loggers
            stat = δ_stats(E, key=logger.key, ϕ=logger.reducer)
            push!(s, stat)
            #println("[$(i)] $(nameof(logger.reducer)) $(logger.key): $(stat)")
        end
        println("Logging to $(LOGGER.csv_path)...")
        log!(LOGGER, s)
        println(LOGGER.table[end, :])
        # FIXME: this is just a placeholder for logging, which will be customized
        # by the client code.
    end
    return E, table
end



function elite_migration!(E)
    src, dst = sample(1:length(E), 2, replace=false)
    i = rand(E[dst].geo.indices)
    if isempty(E[src].elites)
        return
    end
    emigrant = rand(E[src].elites)
    @debug "Elite migration: $(emigrant.name) is moving from Island $(src) to $(dst):$(i)"
    E[dst].geo.deme[i] = emigrant
end


function swap_migration!(E)
    src, dst = sample(1:length(E), 2, replace=false)
    i = rand(E[dst].geo.indices)
    j = rand(E[src].geo.indices)
    @debug "Swap migration: Island $(src), slot $(j) is trading places with Island $(dst), slot $(i)"
    emigrant = E[src].geo.deme[j]
    E[dst].geo.deme[j] = E[src].geo.deme[i]
    E[dst].geo.deme[i] = emigrant
end


# TODO: the islands should execute a bit more asynchronously. maybe pass a DURATION variable,
# and they each run until at least n seconds have passed, THEN they sync up, perhaps migrate, etc.
# this gives you the simplicity of fork/join, and some of the advantages of the async pier model.

end # end module
