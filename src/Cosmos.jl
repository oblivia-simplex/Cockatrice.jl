module Cosmos

using DistributedArrays
using ..Evo
using ..Config


World = DArray{Evo.Evolution,1,Array{Evo.Evolution,1}}


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

    DArray((length(workers),), workers) do I
        [Evo.Evolution(config,
                       creature_type=creature_type,
                       fitness=fitness,
                       crossover=crossover,
                       mutate=mutate,
                       tracers=tracers)]
    end
end


function δ_run(;config="./config.yaml",
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

    config = Config.parse(config)

    for i in 1:config.n_gen
        δ_step!(E; kwargs...)
        if i % config.log_gen != 0
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
    end
end

end # end module
