using Metatheory
using Metatheory.Library
using Metatheory.EGraphs
using Metatheory.Classic
using Metatheory.Util
using Metatheory.EGraphs.Schedulers

## TypeAnalysis
@metatheory_init
# M is a Module
abstract type TypeAnalysis <: AbstractAnalysis end

# This should be auto-generated by a macro
function EGraphs.make(an::Type{TypeAnalysis}, g::EGraph, n::ENode{T}) where T
    if !(T == Expr)
        if ariety(n) == 0
            t = typeof(n.head)
            # other informed type checks on variables should go here
            if n.head == :im
                t = typeof(im)
            end
        else
            # unknown type for CAS
            t = Any
        end
        # println("analyzed type of $n is $t")
        return t
    end

    # T isa Expr
    sym = n.head

    if !(n.metadata.iscall)
        # println("$n is not a call")
        t = Any
        # println("analyzed type of $n is $t")
        return t
    end

    if !(sym isa Symbol)
        # println("head $sym is not a symbol")
        t = Any
        # println("analyzed type of $n is $t")
        return t
    end

    symval = getfield(@__MODULE__, sym)
    child_classes = map(x -> geteclass(g, x), n.args)
    child_types = Tuple(map(x -> getdata(x, an, Any), child_classes))

    # println("symval $symval")
    # println("child types $child_types")

    t_arr = map(last, code_typed(symval, child_types))

    if length(t_arr) == 0
        error("TYPE ERROR. No method for $(n.head) with types $child_types")
    elseif length(t_arr) !== 1
        error("AMBIGUOUS TYPES! $n $t_arr")
    end

    t = t_arr[1]
    # println("inferred type is $t")
    return t
end

EGraphs.join(an::Type{TypeAnalysis}, from, to) = typejoin(from, to)

EGraphs.islazy(x::Type{TypeAnalysis}) = true

##

# display(g.M); println()
# for (k, ec) ∈ g.M
#     println(k)
#     println(collect(ec.nodes))
#     println(getdata(ec, TypeAnalysis, nothing))
# end

function infer(e)
    g = EGraph(e)
    analyze!(g, TypeAnalysis)
    getdata(geteclass(g, g.root), TypeAnalysis)
end


ex1 = :(cos(1 + 3.0) + 4 + (4-4im))
ex2 = :("ciao" * 2)
ex3 = :("ciao" * " mondo")

@test ComplexF64 == infer(ex1)
@test_throws ErrorException infer(ex2)
@test String == infer(ex3)

## Theory for CAS


mult_t = commutative_monoid(:(*), 1)
plus_t = commutative_monoid(:(+), 0)

minus_t = @theory begin
    a - a       => 0
    a + (-b)    => a - b
end

mulplus_t = @theory begin
    a * 0       => 0
    a * (b + c) == ((a*b) + (a*c))
    a + (b * a) => ((b+1)*a)
end

pow_t = @theory begin
    (y^n) * y   => y^(n+1)
    x^n * x^m   == x^(n+m)
    (x * y)^z   == x^z * y^z
    (x^p)^q     == x^(p*q)
    x^0         => 1
    x^1         => x
    inv(x)      == x^(-1)
end

# Dynamic rules
fold_t = @theory begin
    -(a::Number)            |> -a
    a::Number + b::Number   |> a + b
    a::Number * b::Number   |> a * b
end

cas = fold_t ∪ mult_t ∪ plus_t ∪ minus_t ∪ mulplus_t #∪ pow_t

using Metatheory.TermInterface

function customlt(x,y)
    if typeof(x) == Expr && Expr == typeof(y)
        false
    elseif typeof(x) == typeof(y)
        isless(x,y)
    elseif x isa Symbol && y isa Number
        false
    else
        true
    end
end

canonical_t = @theory begin
    # restore n-arity
    (x + (+)(ys...)) => +(x,ys...)
    ((+)(xs...) + y) => +(xs..., y)
    (x * (*)(ys...)) => *(x,ys...)
    ((*)(xs...) * y) => *(xs..., y)

    (*)(xs...)      |> Expr(:call, :*, sort!(xs; lt=customlt)...)
    (+)(xs...)      |> Expr(:call, :+, sort!(xs; lt=customlt)...)
end

macro simplify(ex)
    g = EGraph(ex)
    println(saturate!(g, cas))
    res = extract!(g, astsize)
    println(res)
    # for (id, ec) ∈ g.M
    #     println(id, " => ", collect(ec.nodes))
    #     println("\t\t", getdata(ec, ExtractionAnalysis{astsize}))
    # end
    res = rewrite(res, canonical_t; clean=false, m=__module__)
    Meta.quot(res)
end

@simplify 2a + a + a
@simplify a * c * b
@simplify 1 * x * 2
@simplify (a*b)^2
@simplify a + b + (0*c) + d