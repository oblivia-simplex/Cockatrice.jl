module Cosmos

using Printf
using Serialization
using Distributed
using DistributedArrays
using StatsBase
using Dates
using CSV
using Images
using DataFrames
using ..Names
using ..Evo
using ..Config
using ..Vis
using ..Logging


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
    futs = [@spawnat w begin
            m = filter(isfinite, E[:L][1].trace[key][end])
            isempty(m) ? -Inf : ϕ(m)
            end
            for w in procs(E)]
    m = asyncmap(fetch, futs)
    isempty(m) ? -Inf : ϕ(m)
end


function δ_interaction_matrices(E::World)
    futs = [@spawnat w copy(E[:L][1].geo.interaction_matrix) for w in procs(E)]
    asyncmap(fetch, futs)
end


function get_stats(evo; key="fitness_1", ϕ=mean)
    evo.trace[key][end] |> ϕ
end

function δ_check_stopping_condition(E::World, condition::Function)
    futs = [@spawnat w condition(E[:L][1]) for w in procs(E)]
    asyncmap(fetch, futs) |> findfirst
end

function δ_init(;config=nothing,
                fitness::Function=(_) -> [rand()],
                crossover::Function,
                mutate::Function,
                objective_performance::Function,
                creature_type::DataType,
                tracers=[],
                workers=workers())::DArray

    #trace = Evo.Trace(tracers, config.experiment_duration * 500, config.population.size)
    DArray((length(workers),), workers) do I
        [Evo.Evolution(config,
                       creature_type=creature_type,
                       fitness=fitness,
                       crossover=crossover,
                       mutate=mutate,
                       objective_performance=objective_performance,
                       tracers=tracers)]
    end
end



function run(;config::NamedTuple,
               fitness::Function,
               workers=workers(),
               tracers=[],
               loggers=[],
               mutate::Function,
               crossover::Function,
               creature_type::DataType,
               stopping_condition::Function,
               objective_performance::Function,
               kwargs...)

    if :experiment ∈ keys(config)
        LOGGER = Logger(loggers, config.experiment)
    else
        LOGGER = Logger(loggers)
    end

    evo = Evo.Evolution(config,
                        creature_type=creature_type,
                        fitness=fitness,
                        crossover=crossover,
                        mutate=mutate,
                        objective_performance=objective_performance,
                        tracers=tracers)

    IM_log = []

    for i in 1:config.experiment_duration
        if stopping_condition(evo)
            @info "Stopping condition reached after $(evo.iteration) iterations."
            break
        end

        Evo.step_for_duration!(evo, Second(config.step_duration); kwargs...)


        # Logging
        if i % config.logging.log_every != 0
            continue
        end

        push!(IM_log, copy(evo.geo.interaction_matrix))

        s = []
        for logger in loggers
            push!(s, get_stats(evo, key=logger.key, ϕ=logger.reducer))
        end
        println("Logging to $(LOGGER.log_dir)/$(LOGGER.csv_name)...")
        log!(LOGGER, s)
        println(LOGGER.table[end, :])
        # FIXME: this is just a placeholder for logging, which will be customized
        # by the client code.
    end
    return evo, LOGGER, IM_log
end


function δ_run(;config::NamedTuple,
               fitness::Function,
               workers=workers(),
               tracers=[],
               loggers=[],
               mutate::Function,
               crossover::Function,
               creature_type::DataType,
               stopping_condition::Function,
               objective_performance::Function,
               kwargs...)

    started_at = now()

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
               mutate=mutate,
               objective_performance=objective_performance)

    IM_log = []
    gui = nothing
    for i in 1:config.experiment_duration
        δ_step_for_duration!(E, Second(config.step_duration); kwargs...)

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

        mean_iteration = asyncmap(fetch,
                                  [@spawnat w E[:L][1].iteration for w in procs(E)]
                                  ) |> mean
        s = [mean_iteration]
        for logger in loggers
            push!(s, δ_stats(E, key=logger.key, ϕ=logger.reducer))
        end
        @info("Logging to $(LOGGER.log_dir)/$(LOGGER.csv_name)...")
        log!(LOGGER, s)
        println(LOGGER.table[end, :])

        ims = δ_interaction_matrices(E)
        push!(IM_log, ims)
        log_ims(LOGGER, ims, i)
        images = [Gray.(im) for im in ims]
        gui = Vis.display_images(reshape(images, (2, length(ims)÷2)), gui=gui)

        if (isle = δ_check_stopping_condition(E, stopping_condition)) !== nothing
            @info "Stopping condition reached on Island $(isle)!"
            break
        end

        @info "Total time elapsed: $(now() - started_at)"
    end
    return E, LOGGER, IM_log
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
