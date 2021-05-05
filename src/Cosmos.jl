module Cosmos

using Distributed
using DistributedArrays
using StatsBase
using Dates
using ..Evo
using ..Config


Evolution = Evo.Evolution
World = DArray{Evo.Evolution,1,Array{Evo.Evolution,1}}


function δ_step_for_duration!(E::World, duration::TimePeriod; kwargs...)
    futs = [@spawnat w Evo.step_for_duration!(E[:L][1], duration; kwargs...) for w in procs(E)]
    asyncmap(fetch, futs)
    return
end


function δ_step!(E::World; kwargs...)
    futs = [@spawnat w Evo.step!(E[:L][1]; kwargs...) for w in procs(E)]
    asyncmap(fetch, futs)
    return
end


function δ_stats(E::World; key="fitness:1", ϕ=mean)
    futs = [@spawnat w (w => filter(isfinite, E[:L][1].trace[key][end]) 
                        |> ϕ) for w in procs(E)]
    asyncmap(fetch, futs) |> Dict
end


function δ_init(;config="./config.yaml",
                fitness::Function=(_) -> [rand()],
                crossover::Function,
                mutate::Function,
                creature_type::DataType,
                tracers=[],
                workers=workers())::DArray

    cfg = Config.parse(config)
    trace = Evo.Trace(tracers, cfg.n_gen * 500, cfg.population.size)
    DArray((length(workers),), workers) do I
        [Evo.Evolution(config,
                       creature_type=creature_type,
                       fitness=fitness,
                       crossover=crossover,
                       mutate=mutate,
                       trace=trace,
                       tracers=tracers)]
    end
end


#function δ_run(;genotype_module::Module,
#               kwargs...)
#    δ_run(;creature_type=genotype_module.Creature,
#          crossover=genotype_module.crossover,
#          mutate=genotype_module.mutate!,
#          kwargs...)
#end
#

function δ_run(;config::NamedTuple,
               fitness::Function,
               workers=workers(),
               tracers=[],
               mutate::Function,
               crossover::Function,
               creature_type::DataType,
               kwargs...)

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
        mean_fit = δ_stats(E, key="fitness:1", ϕ=mean)
        max_fit  = δ_stats(E, key="fitness:1", ϕ=maximum)
        mean_gen = δ_stats(E, key="generation", ϕ=mean)
        max_offspring = δ_stats(E, key="num_offspring", ϕ=maximum)
        for w in workers
            pre="[$(i)] Island $(w):"
            println("$pre mean fit = $(mean_fit[w])")
            println("$pre max fit  = $(max_fit[w])")
            println("$pre mean gen = $(mean_gen[w])")
            println("$pre max offs = $(max_offspring[w])")
        end
        # FIXME: this is just a placeholder for logging, which will be customized
        # by the client code.
    end
    return E
end



function elite_migration!(E)
    src, dst = sample(1:length(E), 2, replace=false)
    i = rand(E[dst].geo.indices)
    if isempty(E[src].elites)
        return
    end
    emigrant = rand(E[src].elites)
    @info "Elite migration: $(emigrant.name) is moving from Island $(src) to $(dst):$(i)"
    E[dst].geo.deme[i] = emigrant
end


function swap_migration!(E)
    src, dst = sample(1:length(E), 2, replace=false)
    i = rand(E[dst].geo.indices)
    j = rand(E[src].geo.indices)
    @info "Swap migration: Island $(src), slot $(j) is trading places with Island $(dst), slot $(i)"
    emigrant = E[src].geo.deme[j]
    E[dst].geo.deme[j] = E[src].geo.deme[i]
    E[dst].geo.deme[i] = emigrant
end


# TODO: the islands should execute a bit more asynchronously. maybe pass a DURATION variable,
# and they each run until at least n seconds have passed, THEN they sync up, perhaps migrate, etc.
# this gives you the simplicity of fork/join, and some of the advantages of the async pier model.

end # end module
