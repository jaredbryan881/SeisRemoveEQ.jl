module Get_kurtosis

export get_kurtosis

using Distributions, Statistics, SeisIO

"""
    get_kurtosis(data::SeisChannel,timewinlength::Float64=60)

    compute kurtosis at each timewindow

# Input:
    - `data::SeisData`    : SeisData from SeisIO
    - `timewinlength::Float64`  : time window to calculate kurtosis

    kurtosis evaluation following Baillard et al.(2013)
"""
function get_kurtosis(data::SeisChannel, timewinlength::Float64=60)

    #convert window lengths from seconds to samples
    t1 = @elapsed TimeWin = trunc(Int,timewinlength * data.fs)

    #set long window length to user input since last window of previous channel will have been adjusted
    TimeWin = trunc(Int,timewinlength * data.fs)
    t2 = @elapsed data.misc["kurtosis"] = zeros(Float64, length(data.x))

    i = 0

    t3all = 0
    t4all = 0
    #loop through current channel by sliding
    #while i < length(data.x) - TimeWin
    #    #define chunk of data based on long window length and calculate long-term average
    #    t3 = @elapsed Trace = @views data.x[i+1:i+TimeWin]
    #    #t4 = @elapsed data.misc["kurtosis"][i+TimeWin] = kurtosis(Trace)
    #    t4 = @elapsed data.misc["kurtosis"][i+TimeWin] = kurtosis(Trace)
    #
    #    t3all += t3
    #    t4all += t4
    #    #advance time window
    #    i += 1
    #end
    t4all = @elapsed get_kurtosis!(data, TimeWin)

    #println([t1, t2, t3all, t4all])
    println([t1, t2, t4all])

    return data

end


"""
    fast_kurtosis_series(v::RealArray, TimeWin::Int64)

    fast compute kurtosis series at each timewindow

# Input:
    - `v::RealArray`    : SeisData from SeisIO
    - `N::Int64`  : time window length to calculate kurtosis

    kurtosis evaluation following Baillard et al.(2013)
"""
function fast_kurtosis_series(v::Array{Float64, 1}, TN::Int64)

    kurt = zeros(length(v))
    n = length(v)

    if n < TN error("Kurtosis time window is larger than data length. Decrease time window.") end

    cm2 = 0.0  # empirical 2nd centered moment (variance)
    cm4 = 0.0  # empirical 4th centered moment

    # 1. compute mean value at each time window by numerical sequence
    # 2. use mapreduce to sum values

    # first term
    Trace = @views v[1:TN]
    z2 = zeros(TN)
    m0 = mean(Trace)

    #map!(x -> (x - m0)^2, z2, Trace)
    #cm2 = mapreduce(identity, +, @views z2) / TN
    #cm4 = mapreduce(x->x^2, +, @views z2) / TN

    cm2 = Statistics.varm(Trace, m0, corrected=false)
    cm4 = fourthmoment(Trace, m0, corrected=false)

    # fill first part with kurtosis at TN
    kurt[1:TN] .= (cm4 / (cm2 * cm2)) - 3.0

    t1all = @elapsed @simd for k = TN:n-1

        t5 = @elapsed diff1 = @inbounds (v[k-TN+1] - v[k+1])/TN
        t6 = @elapsed m1 = m0 - diff1

        Trace = @views v[k-TN+2:k+1]

        #t1 = @elapsed map!(x -> abs2.(x - m1), z2, Trace)
        #t1 = @elapsed for l = 1:TN
        #    z2[l] = (Trace[l] - m1)^2
        #end

        t2 = @elapsed cm2 = Statistics.varm(Trace, m1, corrected=false)

        #t2 = @elapsed cm2 = mapreduce(identity, +, z2) / TN
        #t3 = @elapsed cm4_0 = mapreduce(x->x^2, +, z2) / TN

        t8 = @elapsed cm4 = fourthmoment(Trace, m1, corrected=false) #sum(xi - m)^4 / N

        #println([cm4_0, cm4, cm4_0 - cm4])

        t4 = @elapsed kurt[k+1] = (cm4 / (cm2 * cm2)) - 3.0

        # update mean value
        t7 = @elapsed m0 = m1

        #println([t1, t2, t3 , t4 , t5 , t6, t7, t8])
        println([t2, t4 , t5 , t6, t7, t8])

    end

    println([t1all])

    return kurt

end


"""
    get_kurtosis!(data::SeisChannel, TimeWin::Int64)

    get kurtosis series in SeisChannel

# Input:
    - `data::SeisChannel`    : SeisData from SeisIO
    - `timewinlength::Float64`  : time window to calculate kurtosis

    kurtosis evaluation following Baillard et al.(2013)
"""
function get_kurtosis!(data::SeisChannel, TimeWin::Int64)

    kurt = fast_kurtosis_series(data.x, TimeWin)
    data.misc["kurtosis"] = kurt
    return 0

end


#---following functions are modified from Statistics.jl---#

centralizedabs4fun(m) = x -> abs2.(abs2.(x - m))
centralize_sumabs4(A::AbstractArray, m) =
    mapreduce(centralizedabs4fun(m), +, A)
centralize_sumabs4(A::AbstractArray, m, ifirst::Int, ilast::Int) =
    Base.mapreduce_impl(centralizedabs4fun(m), +, A, ifirst, ilast)

function centralize_sumabs4!(R::AbstractArray{S}, A::AbstractArray, means::AbstractArray) where S
    # following the implementation of _mapreducedim! at base/reducedim.jl
    lsiz = Base.check_reducedims(R,A)
    isempty(R) || fill!(R, zero(S))
    isempty(A) && return R

    if Base.has_fast_linear_indexing(A) && lsiz > 16 && !has_offset_axes(R, means)
        nslices = div(length(A), lsiz)
        ibase = first(LinearIndices(A))-1
        for i = 1:nslices
            @inbounds R[i] = centralize_sumabs4(A, means[i], ibase+1, ibase+lsiz)
            ibase += lsiz
        end
        return R
    end
    indsAt, indsRt = Base.safe_tail(axes(A)), Base.safe_tail(axes(R)) # handle d=1 manually
    keep, Idefault = Broadcast.shapeindexer(indsRt)
    if Base.reducedim1(R, A)
        i1 = first(Base.axes1(R))
        @inbounds for IA in CartesianIndices(indsAt)
            IR = Broadcast.newindex(IA, keep, Idefault)
            r = R[i1,IR]
            m = means[i1,IR]
            @simd for i in axes(A, 1)
                r += abs2(abs2(A[i,IA] - m))
            end
            R[i1,IR] = r
        end
    else
        @inbounds for IA in CartesianIndices(indsAt)
            IR = Broadcast.newindex(IA, keep, Idefault)
            @simd for i in axes(A, 1)
                R[i,IR] += abs2(abs2(A[i,IA] - means[i,IR]))
            end
        end
    end
    return R
end

function fourthmoment!(R::AbstractArray{S}, A::AbstractArray, m::AbstractArray; corrected::Bool=true) where S
    if isempty(A)
        fill!(R, convert(S, NaN))
    else
        rn = div(length(A), length(R)) - Int(corrected)
        centralize_sumabs4!(R, A, m)
        R .= R .* (1 // rn)
    end
    return R
end

"""
    fourthmoment(v, m; dims, corrected::Bool=true)
Compute the fourthmoment of a collection `v` with known mean(s) `m`,
optionally over the given dimensions. `m` may contain means for each dimension of
`v`. If `corrected` is `true`, then the sum is scaled with `n-1`,
whereas the sum is scaled with `n` if `corrected` is `false` where `n = length(v)`.
!!! note
    If array contains `NaN` or [`missing`](@ref) values, the result is also
    `NaN` or `missing` (`missing` takes precedence if array contains both).
    Use the [`skipmissing`](@ref) function to omit `missing` entries and compute the
    variance of non-missing values.
"""
fourthmoment(A::AbstractArray, m::AbstractArray; corrected::Bool=true, dims=:) = _fourthmoment(A, m, corrected, dims)

_fourthmoment(A::AbstractArray{T}, m, corrected::Bool, region) where {T} =
    fourthmoment!(Base.reducedim_init(t -> abs2(t)/2, +, A, region), A, m; corrected=corrected)

fourthmoment(A::AbstractArray, m; corrected::Bool=true) = _fourthmoment(A, m, corrected, :)

function _fourthmoment(A::AbstractArray{T}, m, corrected::Bool, ::Colon) where T
    n = length(A)
    n == 0 && return oftype((abs2(zero(T)) + abs2(zero(T)))/2, NaN)
    return centralize_sumabs4(A, m) / (n - Int(corrected))
end

end
