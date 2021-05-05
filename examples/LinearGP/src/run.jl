using Distributed

@everywhere using Pkg
@everywhere Pkg.activate("$(@__DIR__)/../..")
@everywhere Pkg.instantiate()
@everywhere using DistributedArrays
@everywhere using StatsBase
@everywhere using Dates
@everywhere include("$(@__DIR__)/../Cockatrice.jl")

Cosmos = Cockatrice.Cosmos
LinearGP = Cockatrice.LinearGP
Tracer = Cockatrice.Evo.Tracer


DEFAULT_TRACE = [
    Tracer(key="fitness:1", callback=(g -> g.fitness[1])),
    Tracer(key="chromosome_len", callback=(g -> length(g.chromosome))),
    Tracer(key="num_offspring", callback=(g -> g.num_offspring)),
    Tracer(key="generation", callback=(g -> g.generation)),
]


# this one's mostly for REPL use
function init(;config_path="$(@__DIR__)/../../configs/linear_gp.yaml", fitness=nothing, tracers=DEFAULT_TRACE)
    if fitness === nothing
        fitness = get_fitness_function(config_path, FF)
    end
    Cosmos.δ_init(fitness=fitness,
                  crossover=Genotype.crossover,
                  mutate=Genotype.mutate!,
                  creature_type=Genotype.Creature,
                  tracers=tracers)
end


function run(config_path)
    config = Config.parse(config_path)
    fitness_function = Cockatrice.LinearGP.FF.classify
    @assert fitness_function isa Function
    Cosmos.δ_run(config=config,
                 fitness=fitness_function,
                 creature_type=LinearGP.Creature,
                 crossover=LinearGP.crossover,
                 mutate=LinearGP.mutate!,
                 tracers=DEFAULT_TRACE)
end


if !isinteractive()
    config = length(ARGS) > 0 ? ARGS[1] : "$(@__DIR__)/../../configs/linear_gp.yaml"
    run(config)
end

