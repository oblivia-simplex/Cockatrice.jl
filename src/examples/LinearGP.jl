module LinearGP

using Printf

using ..Evo
using ..Names


struct Inst
    op::Function
    arity::Int
    dst::Int
    src::Int
end


Base.@kwdef mutable struct Creature
    chromosome::Vector{Inst}
    effective_code
    phenotype
    fitness::Vector{Float64}
    name::String
    generation::Int
    num_offspring::Int = 0
end


function Creature(config::NamedTuple)
    len = rand(config.genotype.min_len:config.genotype.max_len)
    chromosome = [rand_inst(ops=OPS, num_regs=10) for _ in 1:len]
    fitness = Evo.init_fitness(config)
    Creature(chromosome=chromosome,
             effective_code=nothing,
             phenotype=nothing,
             fitness=fitness,
             name=Names.rand_name(4),
             generation=0)
end


function Base.show(io::IO, inst::Inst)
    op_str = inst.op |> nameof |> String
    if inst.arity == 2
        @printf io "R[%02d] ← R[%02d] %s R[%02d]" inst.dst inst.dst op_str inst.src
    elseif inst.arity == 1
        @printf io "R[%02d] ← %s R[%02d]" inst.dst op_str inst.src
    else # inst.arity == 0
        @printf io "R[%02d] ← %s" inst.dst inst.op()
    end
end

function Creature(chromosome::Vector{Inst})
    Creature(chromosome=chromosome,
             effective_code=nothing,
             phenotype=nothing,
             fitness=[-Inf],
             name=Names.rand_name(4),
             generation=0)
end



function crossover(mother::Creature, father::Creature)::Vector{Creature}
    mother.num_offspring += 1
    father.num_offspring += 1
    mx = rand(1:length(mother.chromosome))
    fx = rand(1:length(father.chromosome))
    chrom1 = [mother.chromosome[1:mx]; father.chromosome[(fx+1):end]]
    chrom2 = [father.chromosome[1:fx]; mother.chromosome[(mx+1):end]]
    children = Creature.([chrom1, chrom2])
    generation = max(mother.generation, father.generation) + 1
    (c -> c.generation = generation).(children)
    (c -> c.fitness = Evo.init_fitness(mother.fitness)).(children)
    children
end


function mutate!(creature::Creature; config=nothing)
    inds = keys(creature.chromosome)
    i = rand(inds)
    creature.chromosome[i] = rand_inst(ops=OPS, num_regs=10) # FIXME hardcoded
    return
end

"""Safe division"""
⊘(a,b) = iszero(b) ? a : a/b

constant(c) = () -> c

safelog(n) = sign(n) * log(abs(n))


OPS = [
    (⊘, 2),
    (+, 2),
    (-, 2),
    (*, 2),
    (safelog, 1),
    (cos, 1),
    (sin, 1),
    (identity, 1),
    (constant(π), 0),
    (constant(1), 0),
    (constant(0), 0),
    (constant(ℯ), 0),
]


function rand_inst(;ops=OPS, num_regs=10)
    op, arity = rand(ops)
    dst = rand(1:num_regs)
    src = rand(1:num_regs)
    Inst(op, arity, dst, src)
end


function evaluate_inst!(;regs::Vector{Float64}, inst::Inst)
    if inst.arity == 2
        args = regs[[inst.dst, inst.src]]
    elseif inst.arity == 1
        args = regs[inst.src]
    else # inst.arity == 0
        args = []
    end
    regs[inst.dst] = inst.op(args...)
end


function evaluate(;regs::Vector{Float64}, args::Vector{Float64}, code::Vector)
    regs = copy(regs)
    regs[1:length(args)] = args
    for inst in code
        evaluate_inst!(regs=regs, inst=inst)
    end
    regs
end


function strip_introns(code, out_regs)
    active_regs = copy(out_regs)
    active_insts = []
    for inst in reverse(code)
        if inst.dst ∈ active_regs 
            push!(active_insts, inst)
            filter!(r -> r != inst.dst, active_regs)
            if inst.arity == 2
                push!(active_regs, inst.dst)
            end
            if inst.arity ≥ 1
                push!(active_regs, inst.src)
            end
        end
    end
    reverse(active_insts)
end

module FF

using RDatasets
using ..LinearGP

function _get_categorical_dataset(name)
    data = dataset("datasets", "iris")
    columns = names(data)
    class_col = columns[end]
    classes = data[:, class_col] |> unique
    classnum(s) = findfirst(x -> x == s, classes) |> Float64
    data[!, class_col] = classnum.(data[:, class_col])
    return data, classes
end

DATA, CLASSES = _get_categorical_dataset("iris")

NUM_REGS = 10

function classify(g; strip_introns=true)
    regs = zeros(Float64, NUM_REGS) # FIXME shouldn't be hardcoded, pass config to ff?
    outregs = collect((1 + length(regs) - length(CLASSES)):length(regs))
    code = g.chromosome
    if strip_introns
        if g.effective_code === nothing
            g.effective_code = LinearGP.strip_introns(g.chromosome, outregs)
        end
        code = g.effective_code
    end
    if length(code) == 0 return [0.0, 0.0] end
    correct = 0
    choices = []
    for row in eachrow(DATA)
        r = collect(row)
        class = r[end]
        args = r[1:end-1]
        res_regs = LinearGP.evaluate(regs=regs, args=args, code=code)
        output = res_regs[outregs]
        ranking = sort(keys(output), by = i -> output[i])
        choice = ranking[end]
        push!(choices, choice)
        if choice == class
            correct += 1
        end
    end
    g.phenotype = choices
    accuracy = correct / length(eachrow(DATA))
    parsimony = 1.0 / length(g.chromosome)
    effective_parsimony = 1.0 / length(code)
    return [accuracy, effective_parsimony, parsimony]
end

end # end FF



end # module LinearGP
