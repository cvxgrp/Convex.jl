#############################################################################
# variable.jl
# Defines Variable, which is a subtype of AbstractExpr
#############################################################################

export Variable, Semidefinite, ComplexVariable, HermitianSemidefinite
export vexity, evaluate, sign, conic_form!, fix!, free!

export BinVar, IntVar, ContVar, vartype, vartype!

"""
    VarType

Describe the type of a `Variable`: either continuous (`ContVar`), integer-valued (`IntVar`), or binary (`BinVar`).
"""
@enum VarType BinVar IntVar ContVar

@doc "Indicates a `Variable` is a binary variable." BinVar
@doc "Indicates a `Variable` is integer-valued." IntVar
@doc "Indicates a `Variable` is continuous." ContVar

"""
    abstract type AbstractVariable <: AbstractExpr end

An `AbstractVariable` should have `head` field, an `id_hash` field and a `size` field
to conform to the `AbstractExpr` interface, and implement methods (or use the field-access fallbacks) for

* `value`, `value!`: get or set the numeric value of the variable. `value` should return `nothing` when no numeric value is set.
* `vexity`, `vexity!`: get or set the `vexity` of the variable. The `vexity` should be `AffineVexity()` unless the variable has been `fix!`'d, in which case it is `ConstVexity()`.
* `sign`, `vartype`, `eltype`, and `constraints`: get the `Sign`, `VarType`, numeric type, and a (possibly empty) vector of constraints which are to be applied to any problem in which the variable is used.

Optionally, also implement `sign!`, `vartype!`, and `constraints!` to allow users to modify those values. Moreover, when an `AbstractVariable` `x` is constructed, it should populate `Convex.id_to_variables` via, e.g.
```
Convex.id_to_variables(x.id_hash) = x
```

"""
abstract type AbstractVariable <: AbstractExpr end

# Default implementation of `AbstractVariable` interface
constraints(x::AbstractVariable) = x.constraints
constraints!(x::AbstractVariable, L::Vector{Constraint}) = x.constraints = L

vartype(x::AbstractVariable) = x.vartype
vartype!(x::AbstractVariable, vt::VarType) = x.vartype = vt

vexity(x::AbstractVariable) = x.vexity
vexity!(x::AbstractVariable, v::Vexity) = x.vexity = v

sign(x::AbstractVariable) = x.sign
sign!(x::AbstractVariable, s::Sign) = x.sign = s

eltype(x::AbstractVariable) = sign(x) == ComplexSign() ? Complex{Float64} :  Float64

value(x::AbstractVariable) = x.value

function value!(x::AbstractVariable, v::AbstractArray)
    size(x) == size(v) || throw(DimensionMismatch("Variable and value sizes do not match!"))
    x.value = convert(Array{eltype(x)}, v)
end

function value!(x::Variable, v::AbstractVector)
    size(x, 2) == 1 || throw(DimensionMismatch("Cannot set value of a variable of size $(size(x)) to a vector"))
    size(x, 1) == length(v) || throw(DimensionMismatch("Variable and value sizes do not match!"))
    x.value = convert(Array{eltype(x)}, v)
end

function value!(x::AbstractVariable, v::Number)
    size(x) == (1,1) || throw(DimensionMismatch("Variable and value sizes do not match!"))
    x.value = convert(eltype(x), v)
end


# A concrete implementation of the `AbstractVariable` interface
mutable struct Variable <: AbstractVariable
    """
    Every `AbstractExpr` has a `head`; for a Variable it is set to `:variable`.
    """
    head::Symbol
    """
    A unique identifying hash used for caching.
    """
    id_hash::UInt64
    """
    The current value of the variable. Defaults to `nothing` until the variable has been
    [`fix!`](@ref)'d to a particular value, or the variable has been used in a problem which
    has been solved, at which point the optimal value is populated into this field.
    """
    value::ValueOrNothing
    """
    The size of the variable. Scalar variables have size `(1,1)`; `d`-dimensional vectors have
    size `(d, 1)`, and `n` by `m` matrices have size `(n,m)`.
    """
    size::Tuple{Int, Int}
    """
    `AffineVexity()` unless the variable is `fix!`'d, in which case it is `ConstVexity()`.
    Accessed by `vexity(v::Variable)`. To check if a `Variable` is fixed, use `vexity(v) == ConstVexity()`.
    """
    vexity::Vexity
    """
    The sign of the variable. Can be  `Positive()`, `Negative()`, `NoSign()` (i.e. real), or `ComplexSign()`.
    Accessed by `sign(v::Variable)`. 
    """
    sign::Sign
    """
    Vector of constraints which are enforced whenever the variable is used in a problem.
    """
    constraints::Vector{Constraint}
    """
    The `VarType` of the variable (binary, integer, or continuous).
    """
    vartype::VarType
    function Variable(size::Tuple{Int, Int}, sign::Sign=NoSign(), constraint_fns...; vartype = ContVar)
        this = new(:variable, 0, nothing, size, AffineVexity(), sign, Constraint[], vartype)

        # now that we have access to the variable (`this`), we can apply constraints to it.
        for f in constraint_fns
            push!(this.constraints, f(this))
        end

        this.id_hash = objectid(this)
        id_to_variables[this.id_hash] = this
        return this
    end

    Variable(m::Int, n::Int, sign::Sign=NoSign(), constraint_fns...) = Variable((m,n), sign, constraint_fns...)
    Variable(sign::Sign, constraint_fns...) = Variable((1, 1), sign, constraint_fns...)
    Variable(constraint_fns...) = Variable((1, 1), NoSign(), constraint_fns...)
    Variable(size::Tuple{Int, Int}, constraint_fns...) = Variable(size, NoSign(), constraint_fns...)
    Variable(size::Int, sign::Sign=NoSign(), constraint_fns...) = Variable((size, 1), sign, constraint_fns...)
    Variable(size::Int, constraint_fns...) = Variable((size, 1), constraint_fns...)
end

# Compatability with old `sets` model
# Only dispatch to these methods when at least one set is given
# Otherwise dispatch to the inner constructors
function Variable(size::Tuple{Int, Int}, sign::Sign, first_set::Symbol, more_sets::Symbol...)
    sets = [first_set]
    append!(sets, more_sets)
    if :Bin in sets
        vartype = BinVar
    elseif :Int in sets
        vartype = IntVar
    else
        vartype = ContVar
    end
    if :Semidefinite in sets
        fns = [ x -> x ⪰ 0 ]
    else
        fns = []
    end
    Variable(size, sign, fns...; vartype = vartype)
end


Variable(m::Int, n::Int, sign::Sign, first_set::Symbol, more_sets::Symbol...) = Variable((m,n), sign, first_set, more_sets...)
Variable(m::Int, n::Int, first_set::Symbol, more_sets::Symbol...) = Variable((m,n), NoSign(), first_set, more_sets...)

Variable(sign::Sign, first_set::Symbol, more_sets::Symbol...) = Variable((1, 1), sign, first_set, more_sets...)
Variable(first_set::Symbol, more_sets::Symbol...) = Variable((1, 1), NoSign(), first_set, more_sets...)
Variable(size::Tuple{Int, Int},first_set::Symbol, more_sets::Symbol...) = Variable(size, NoSign(), first_set, more_sets...)
Variable(size::Int, sign::Sign, first_set::Symbol, more_sets::Symbol...) = Variable((size, 1), sign, first_set, more_sets...)
Variable(size::Int, first_set::Symbol, more_sets::Symbol...) = Variable((size, 1), NoSign(), first_set, more_sets...)

Semidefinite(m::Integer) = Variable((m, m), x -> x ⪰ 0)
function Semidefinite(m::Integer, n::Integer)
    if m == n
        return Variable((m, m), x -> x ⪰ 0)
    else
        error("Semidefinite matrices must be square")
    end
end

ComplexVariable(m::Int, n::Int, constraint_fns...) = Variable((m, n), ComplexSign(), constraint_fns...)
ComplexVariable(m::Int, n::Int, first_set::Symbol, more_sets::Symbol...) = Variable((m, n), ComplexSign(), first_set, more_sets...)

ComplexVariable(constraint_fns...) = Variable((1, 1), ComplexSign(), constraint_fns...)
ComplexVariable(first_set::Symbol, more_sets::Symbol...) = Variable((1, 1), ComplexSign(), first_set, more_sets...)

ComplexVariable(size::Tuple{Int, Int}, constraint_fns...) = Variable(size, ComplexSign(), constraint_fns...)
ComplexVariable(size::Tuple{Int, Int}, first_set::Symbol, more_sets::Symbol...) = Variable(size, ComplexSign(), first_set, more_sets...)

ComplexVariable(size::Int, constraint_fns...) = Variable((size, 1), ComplexSign(), constraint_fns...)
ComplexVariable(size::Int, first_set::Symbol, more_sets::Symbol...) = Variable((size, 1), ComplexSign(), first_set, more_sets...)

HermitianSemidefinite(m::Integer) = ComplexVariable((m, m), x -> x ⪰ 0)
function HermitianSemidefinite(m::Integer, n::Integer)
    if m == n
        return ComplexVariable((m, m), x -> x ⪰ 0)
    else
        error("`HermitianSemidefinite` matrices must be square")
    end
end

# global map from unique variable ids to variables.
# the expression tree will only utilize variable ids during construction
# full information of the variables will be needed during stuffing
# and after solving to populate the variables with values
const id_to_variables = Dict{UInt64, AbstractVariable}()

function evaluate(x::AbstractVariable)
    return value(x) === nothing ? error("Value of the variable is yet to be calculated") : value(x)
end

function real_conic_form(x::AbstractVariable)
    vec_size = length(x)
    return sparse(1.0I, vec_size, vec_size)
end

function imag_conic_form(x::AbstractVariable)
    vec_size = length(x)
    if sign(x) == ComplexSign()
        return im*sparse(1.0I, vec_size, vec_size)
    else
        return spzeros(vec_size, vec_size)
    end
end

function conic_form!(x::AbstractVariable, unique_conic_forms::UniqueConicForms=UniqueConicForms())
    if !has_conic_form(unique_conic_forms, x)
        if vexity(x) == ConstVexity()
            # do exactly what we would for a constant
            objective = ConicObj()
            objective[objectid(:constant)] = (vec([real(value(x));]),vec([imag(value(x));]))
            cache_conic_form!(unique_conic_forms, x, objective)
        else
            objective = ConicObj()
            vec_size = length(x)

            objective[x.id_hash] = (real_conic_form(x), imag_conic_form(x))
            objective[objectid(:constant)] = (spzeros(vec_size, 1), spzeros(vec_size, 1))
            # placeholder values in unique constraints prevent infinite recursion depth
            cache_conic_form!(unique_conic_forms, x, objective)
            if !(sign(x) == NoSign() || sign(x) == ComplexSign())
                conic_form!(sign(x), x, unique_conic_forms)
            end

            # apply the constraints `x` itself carries
            for constraint in constraints(x)
                conic_form!(constraint, unique_conic_forms)
            end
        end
    end
    return get_conic_form(unique_conic_forms, x)
end

# fix variables to hold them at their current value, and free them afterwards
function fix!(x::AbstractVariable)
    value(x) === nothing && error("This variable has no value yet; cannot fix value to nothing!")
    vexity!(x, ConstVexity())
    x
end

function fix!(x::AbstractVariable, v)
    value!(x, v)
    fix!(x)
end

function free!(x::AbstractVariable)
    vexity!(x, AffineVexity())
    x
end
