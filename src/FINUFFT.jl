__precompile__()
module FINUFFT

## Export
export nufft1d1, nufft1d2, nufft1d3
export nufft2d1, nufft2d2, nufft2d3
export nufft3d1, nufft3d2, nufft3d3

export nufft1d1!, nufft1d2!, nufft1d3!
export nufft2d1!, nufft2d2!, nufft2d3!
export nufft3d1!, nufft3d2!, nufft3d3!

export nufftf1d1, nufftf1d2, nufftf1d3
export nufftf2d1, nufftf2d2, nufftf2d3
export nufftf3d1, nufftf3d2, nufftf3d3

export nufftf1d1!, nufftf1d2!, nufftf1d3!
export nufftf2d1!, nufftf2d2!, nufftf2d3!
export nufftf3d1!, nufftf3d2!, nufftf3d3!

export nufft_opts
export nufft_c_opts # backward-compability
export finufft_default_opts
export finufft_makeplan
export finufft_setpts
export finufft_exec
export finufft_destroy
export finufftf_default_opts
export finufftf_makeplan
export finufftf_setpts
export finufftf_exec
export finufftf_destroy
export BIGINT

## External dependencies
using Libdl

const depsfile = joinpath(dirname(@__DIR__), "deps", "deps.jl")
if isfile(depsfile)
    include(depsfile)
else
    error("FINUFFT is not properly installed. Please build it first.")
end

function __init__()
    Libdl.dlopen(fftw, Libdl.RTLD_GLOBAL)       
    if !Sys.iswindows()
        Libdl.dlopen(fftw_threads, Libdl.RTLD_GLOBAL)
    end
end

const BIGINT = Int64 # defined in include/dataTypes.h


## FINUFFT opts struct from include/nufft_opts.h
"""
    mutable struct nufft_opts    
        debug              :: Cint
        spread_debug       :: Cint
        spread_sort        :: Cint
        spread_kerevalmeth :: Cint
        spread_kerpad      :: Cint
        chkbnds            :: Cint
        fftw               :: Cint
        modeord            :: Cint
        upsampfac          :: Cdouble
        spread_thread      :: Cint
        maxbatchsize       :: Cint
        nthreads           :: Cint
        showwarn           :: Cint
    end

Options struct passed to the FINUFFT library.

# Fields

    debug :: Cint
0: silent, 1: text basic timing output

    spread_debug :: Cint
passed to spread_opts, 0 (no text) 1 (some) or 2 (lots)

    spread_sort :: Cint
passed to spread_opts, 0 (don't sort) 1 (do) or 2 (heuristic)

    spread_kerevalmeth :: Cint
passed to spread_opts, 0: exp(sqrt()), 1: Horner ppval (faster)

    spread_kerpad :: Cint
passed to spread_opts, 0: don't pad to mult of 4, 1: do

    chkbnds :: Cint
0: don't check if input NU pts in [-3pi,3pi], 1: do

    fftw :: Cint
0:`FFTW_ESTIMATE`, or 1:`FFTW_MEASURE` (slow plan but faster)

    modeord :: Cint
0: CMCL-style increasing mode ordering (neg to pos), or\\
1: FFT-style mode ordering (affects type-1,2 only)

    upsampfac :: Cdouble
upsampling ratio sigma, either 2.0 (standard) or 1.25 (small FFT)

    spread_thread :: Cint
for ntrans>1 only.\\
0:auto,\\
1: sequential multithreaded,\\
2: parallel singlethreaded (Melody),\\
3: nested multithreaded (Andrea).

    maxbatchsize :: Cint
// for ntrans>1 only. max blocking size for vectorized, 0 for auto-set

    spread_nthr_atomic :: Cint
if >=0, threads above which spreader OMP critical goes atomic
    spread_max_sp_size :: Cint
if >0, overrides spreader (dir=1) max subproblem size
"""
mutable struct nufft_opts    
    modeord            :: Cint
    chkbnds            :: Cint
    debug              :: Cint
    spread_debug       :: Cint
    showwarn           :: Cint
    nthreads           :: Cint
    fftw               :: Cint
    spread_sort        :: Cint
    spread_kerevalmeth :: Cint
    spread_kerpad      :: Cint
    upsampfac          :: Cdouble
    spread_thread      :: Cint
    maxbatchsize       :: Cint
    spread_nthr_atomic :: Cint
    spread_max_sp_size :: Cint
end

const nufft_c_opts = nufft_opts # backward compability

"""
    finufft_default_opts()

Return a [`nufft_opts`](@ref) struct with the default FINUFFT settings.\\
See: <https://finufft.readthedocs.io/en/latest/usage.html#options>
"""
function finufft_default_opts()
    opts = nufft_opts(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    ccall( (:finufft_default_opts, libfinufft),
           Nothing,
           (Ref{nufft_opts},),
           opts
           )
    return opts
end

function finufftf_default_opts()
    opts = nufft_opts(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    ccall( (:finufftf_default_opts, libfinufft),
           Nothing,
           (Ref{nufft_opts},),
           opts
           )
    return opts
end

### Error handling
const ERR_EPS_TOO_SMALL        = 1
const ERR_MAXNALLOC            = 2
const ERR_SPREAD_BOX_SMALL     = 3
const ERR_SPREAD_PTS_OUT_RANGE = 4
const ERR_SPREAD_ALLOC         = 5
const ERR_SPREAD_DIR           = 6
const ERR_UPSAMPFAC_TOO_SMALL  = 7
const HORNER_WRONG_BETA        = 8
const ERR_NDATA_NOTVALID       = 9
const ERR_TYPE_UNDEF           = 10
const ERR_ALLOC                = 11
const ERR_NDIM                 = 12
const ERR_SPREAD_THREAD_NOTVALID = 13

struct FINUFFTError <: Exception
    errno::Cint
    msg::String
end
Base.showerror(io::IO, e::FINUFFTError) = print(io, "FINUFFT Error ($(e.errno)): ", e.msg)

function check_ret(ret)
    # Check return value and output error messages
    if ret==0
        return
    elseif ret==ERR_EPS_TOO_SMALL
        msg = "requested tolerance epsilon too small"
    elseif ret==ERR_MAXNALLOC
        msg = "attemped to allocate internal arrays larger than MAX_NF (defined in common.h)"
    elseif ret==ERR_SPREAD_BOX_SMALL
        msg = "spreader: fine grid too small"
    elseif ret==ERR_SPREAD_PTS_OUT_RANGE
        msg = "spreader: if chkbnds=1, a nonuniform point out of input range [-3pi,3pi]^d"
    elseif ret==ERR_SPREAD_ALLOC
        msg = "spreader: array allocation error"
    elseif ret==ERR_SPREAD_DIR
        msg = "spreader: illegal direction (should be 1 or 2)"
    elseif ret==ERR_UPSAMPFAC_TOO_SMALL
        msg = "upsampfac too small (should be >1)"
    elseif ret==HORNER_WRONG_BETA
        msg = "upsampfac not a value with known Horner eval: currently 2.0 or 1.25 only"
    elseif ret==ERR_NDATA_NOTVALID
        msg = "ndata not valid (should be >= 1)"
    elseif ret==ERR_TYPE_UNDEF
        msg = "undefined type, type should be 1, 2, or 3"
    elseif ret==ERR_NDIM
        msg = "dimension should be 1, 2, or 3"
    elseif ret==ERR_ALLOC
        msg = "allocation error"
    elseif ret==ERR_SPREAD_THREAD_NOTVALID
        msg = "spread thread not valid"
    else
        msg = "unknown error"
    end
    throw(FINUFFTError(ret, msg))
end


### Guru Interfaces
mutable struct finufft_plan_s
end
mutable struct finufftf_plan_s
end
finufft_plan = Ptr{finufft_plan_s}
finufftf_plan = Ptr{finufftf_plan_s}

### Double precision
function finufft_makeplan(type::Integer,
                          dim::Integer,
                          n_modes::Array{BIGINT},
                          iflag::Integer,
                          ntrans::Integer,
                          eps::Float64,
                          opts::nufft_opts=finufft_default_opts())
    plan = ccall( (:finufft_plan_alloc, libfinufft),
                 finufft_plan,
                 (Cint,
                  Cint,
                  Ref{BIGINT},
                  Cint,
                  Cint,
                  Cdouble,
                  Ref{nufft_opts}),
                 type,dim,n_modes,iflag,ntrans,eps,opts
                 )
    return plan
end

function finufft_setpts(plan::finufft_plan,
                        M::Integer,
                        xj::Array{Float64},
                        yj::Array{Float64},
                        zj::Array{Float64},
                        N::Integer,
                        s::Array{Float64},
                        t::Array{Float64},
                        u::Array{Float64})
    ret = ccall( (:finufft_setpts, libfinufft),
                 Cint,
                 (finufft_plan,
                  BIGINT,
                  Ref{Cdouble},
                  Ref{Cdouble},
                  Ref{Cdouble},
                  BIGINT,
                  Ref{Cdouble},
                  Ref{Cdouble},
                  Ref{Cdouble}),
                 plan,M,xj,yj,zj,N,s,t,u
                 )
    check_ret(ret)
    return ret
end

function finufft_exec(plan::finufft_plan,
                      input::Array{ComplexF64})
    type = ccall( (:get_type, libfinufft),
                  Cint,
                  (finufft_plan,),
                  plan
                  )
    ntrans = ccall( (:get_ntransf, libfinufft),
                    Cint,
                    (finufft_plan,),
                    plan
                    )
    ndim = ccall( (:get_ndims, libfinufft),
                  Cint,
                  (finufft_plan,),
                  plan
                  )
    n_modes = Array{BIGINT}(undef,3)
    if type==1
        ccall( (:get_nmodes, libfinufft),
               Cvoid,
               (finufft_plan,
                Ref{BIGINT}),
               plan,n_modes
               )
        if ndim==1
            output = Array{ComplexF64}(undef,n_modes[1],ntrans)
        elseif ndim==2
            output = Array{ComplexF64}(undef,n_modes[1],n_modes[2],ntrans)
        elseif ndim==3
            output = Array{ComplexF64}(undef,n_modes[1],n_modes[2],n_modes[3],ntrans)
        else
            ret = ERR_NDIM
            check_ret(ret)
        end
        ret = ccall( (:finufft_execute, libfinufft),
                     Cint,
                     (finufft_plan,
                      Ref{ComplexF64},
                      Ref{ComplexF64}),
                     plan,input,output
                     )
    elseif type==2
        nj = ccall( (:get_nj, libfinufft),
                    BIGINT,
                    (finufft_plan,),
                    plan
                    )
        output = Array{ComplexF64}(undef,nj,ntrans)
        ret = ccall( (:finufft_exec, libfinufft),
                     Cint,
                     (finufft_plan,
                      Ref{ComplexF64},
                      Ref{ComplexF64}),
                     plan,output,input
                     )
    elseif type==3
        nk = ccall( (:get_nk, libfinufft),
                    BIGINT,
                    (finufft_plan,),
                    plan
                    )
        output = Array{ComplexF64}(undef,nk,ntrans)
        ret = ccall( (:finufft_exec, libfinufft),
                     Cint,
                     (finufft_plan,
                      Ref{ComplexF64},
                      Ref{ComplexF64}),
                     plan,input,output
                     )
    else
        ret = ERR_TYPE_UNDEF
    end
    check_ret(ret)
    return output
end

function finufft_destroy(plan::finufft_plan)
    ret = ccall( (:finufft_destroy, libfinufft),
                 Cint,
                 (finufft_plan,),
                 plan
                 )
    check_ret(ret)
    return ret
end


### Single precision
function finufftf_makeplan(type::Integer,
                          dim::Integer,
                          n_modes::Array{BIGINT},
                          iflag::Integer,
                          ntrans::Integer,
                          eps::Float32,
                          opts::nufft_opts=finufftf_default_opts())
    plan = ccall( (:finufftf_plan_alloc, libfinufft),
                 finufftf_plan,
                 (Cint,
                  Cint,
                  Ref{BIGINT},
                  Cint,
                  Cint,
                  Cfloat,
                  Ref{nufft_opts}),
                 type,dim,n_modes,iflag,ntrans,eps,opts
                 )
    return plan
end

function finufftf_setpts(plan::finufftf_plan,
                        M::Integer,
                        xj::Array{Float32},
                        yj::Array{Float32},
                        zj::Array{Float32},
                        N::Integer,
                        s::Array{Float32},
                        t::Array{Float32},
                        u::Array{Float32})
    ret = ccall( (:finufftf_setpts, libfinufft),
                 Cint,
                 (finufftf_plan,
                  BIGINT,
                  Ref{Cfloat},
                  Ref{Cfloat},
                  Ref{Cfloat},
                  BIGINT,
                  Ref{Cfloat},
                  Ref{Cfloat},
                  Ref{Cfloat}),
                 plan,M,xj,yj,zj,N,s,t,u
                 )
    check_ret(ret)
    return ret
end

function finufftf_exec(plan::finufftf_plan,
                      input::Array{ComplexF32})
    type = ccall( (:getf_type, libfinufft),
                  Cint,
                  (finufftf_plan,),
                  plan
                  )
    ntrans = ccall( (:getf_ntransf, libfinufft),
                    Cint,
                    (finufftf_plan,),
                    plan
                    )
    ndim = ccall( (:getf_ndims, libfinufft),
                  Cint,
                  (finufftf_plan,),
                  plan
                  )
    n_modes = Array{BIGINT}(undef,3)
    if type==1
        ccall( (:getf_nmodes, libfinufft),
               Cvoid,
               (finufftf_plan,
                Ref{BIGINT}),
               plan,n_modes
               )
        if ndim==1
            output = Array{ComplexF32}(undef,n_modes[1],ntrans)
        elseif ndim==2
            output = Array{ComplexF32}(undef,n_modes[1],n_modes[2],ntrans)
        elseif ndim==3
            output = Array{ComplexF32}(undef,n_modes[1],n_modes[2],n_modes[3],ntrans)
        else
            ret = ERR_NDIM
            check_ret(ret)
        end
        ret = ccall( (:finufftf_execute, libfinufft),
                     Cint,
                     (finufftf_plan,
                      Ref{ComplexF32},
                      Ref{ComplexF32}),
                     plan,input,output
                     )
    elseif type==2
        nj = ccall( (:getf_nj, libfinufft),
                    BIGINT,
                    (finufftf_plan,),
                    plan
                    )
        output = Array{ComplexF32}(undef,nj,ntrans)
        ret = ccall( (:finufftf_execute, libfinufft),
                     Cint,
                     (finufftf_plan,
                      Ref{ComplexF32},
                      Ref{ComplexF32}),
                     plan,output,input
                     )
    elseif type==3
        nk = ccall( (:getf_nk, libfinufft),
                    BIGINT,
                    (finufftf_plan,),
                    plan
                    )
        output = Array{ComplexF32}(undef,nk,ntrans)
        ret = ccall( (:finufftf_execute, libfinufft),
                     Cint,
                     (finufftf_plan,
                      Ref{ComplexF32},
                      Ref{ComplexF32}),
                     plan,input,output
                     )
    else
        ret = ERR_TYPE_UNDEF
    end
    check_ret(ret)
    return output
end

function finufftf_destroy(plan::finufftf_plan)
    ret = ccall( (:finufftf_destroy, libfinufft),
                 Cint,
                 (finufftf_plan,),
                 plan
                 )
    check_ret(ret)
    return ret
end


### Simple Interfaces (allocate output)
### Double precision
## Type-1

"""
    nufft1d1(xj      :: Array{Float64}, 
             cj      :: Array{ComplexF64}, 
             iflag   :: Integer, 
             eps     :: Float64,
             ms      :: Integer
             [, opts :: nufft_opts]
            ) -> Array{ComplexF64}

Compute type-1 1D complex nonuniform FFT. 
"""
function nufft1d1(xj::Array{Float64},
                  cj::Array{ComplexF64},
                  iflag::Integer,
                  eps::Float64,
                  ms::Integer,
                  opts::nufft_opts=finufft_default_opts())
    ntrans = convert(Int64, round(length(cj)/length(xj), digits=0))
    fk = Array{ComplexF64}(undef, ms, ntrans)
    nufft1d1!(xj, cj, iflag, eps, fk, opts)
    return fk
end

"""
    nufft2d1(xj      :: Array{Float64}, 
             yj      :: Array{Float64}, 
             cj      :: Array{ComplexF64}, 
             iflag   :: Integer, 
             eps     :: Float64,
             ms      :: Integer,
             mt      :: Integer,
             [, opts :: nufft_opts]
            ) -> Array{ComplexF64}

Compute type-1 2D complex nonuniform FFT.
"""
function nufft2d1(xj      :: Array{Float64}, 
                  yj      :: Array{Float64}, 
                  cj      :: Array{ComplexF64}, 
                  iflag   :: Integer, 
                  eps     :: Float64,
                  ms      :: Integer,
                  mt      :: Integer,                   
                  opts    :: nufft_opts = finufft_default_opts())
    ntrans = convert(Int64, round(length(cj)/length(xj), digits=0))
    fk = Array{ComplexF64}(undef, ms, mt, ntrans)
    nufft2d1!(xj, yj, cj, iflag, eps, fk, opts)
    return fk
end

"""
    nufft3d1(xj      :: Array{Float64}, 
             yj      :: Array{Float64}, 
             zj      :: Array{Float64}, 
             cj      :: Array{ComplexF64}, 
             iflag   :: Integer, 
             eps     :: Float64,
             ms      :: Integer,
             mt      :: Integer,
             mu      :: Integer,
             [, opts :: nufft_opts]
            ) -> Array{ComplexF64}

Compute type-1 3D complex nonuniform FFT.
"""
function nufft3d1(xj      :: Array{Float64}, 
                  yj      :: Array{Float64},
                  zj      :: Array{Float64},                   
                  cj      :: Array{ComplexF64}, 
                  iflag   :: Integer, 
                  eps     :: Float64,
                  ms      :: Integer,
                  mt      :: Integer,
                  mu      :: Integer,                                     
                  opts    :: nufft_opts = finufft_default_opts())
    ntrans = convert(Int64, round(length(cj)/length(xj), digits=0))
    fk = Array{ComplexF64}(undef, ms, mt, mu, ntrans)
    nufft3d1!(xj, yj, zj, cj, iflag, eps, fk, opts)
    return fk
end


## Type-2

"""
    nufft1d2(xj      :: Array{Float64}, 
             iflag   :: Integer, 
             eps     :: Float64,
             fk      :: Array{ComplexF64} 
             [, opts :: nufft_opts]
            ) -> Array{ComplexF64}

Compute type-2 1D complex nonuniform FFT. 
"""
function nufft1d2(xj      :: Array{Float64},                    
                  iflag   :: Integer, 
                  eps     :: Float64,
                  fk      :: Array{ComplexF64},
                  opts    :: nufft_opts = finufft_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==1 || ndim==2
    if ndim==1
       ntrans = 1
    else
       ms, ntrans = size(fk)
    end
    cj = Array{ComplexF64}(undef, nj, ntrans)
    nufft1d2!(xj, cj, iflag, eps, fk, opts)
    return cj
end

"""
    nufft2d2(xj      :: Array{Float64}, 
             yj      :: Array{Float64}, 
             iflag   :: Integer, 
             eps     :: Float64,
             fk      :: Array{ComplexF64} 
             [, opts :: nufft_opts]
            ) -> Array{ComplexF64}

Compute type-2 2D complex nonuniform FFT. 
"""
function nufft2d2(xj      :: Array{Float64}, 
                  yj      :: Array{Float64}, 
                  iflag   :: Integer, 
                  eps     :: Float64,
                  fk      :: Array{ComplexF64},
                  opts    :: nufft_opts = finufft_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==2 || ndim==3
    if ndim==2
       ntrans = 1
    else
       ms, mt, ntrans = size(fk)
    end
    cj = Array{ComplexF64}(undef, nj, ntrans)
    nufft2d2!(xj, yj, cj, iflag, eps, fk, opts)
    return cj
end

"""
    nufft3d2(xj      :: Array{Float64}, 
             yj      :: Array{Float64}, 
             zj      :: Array{Float64}, 
             iflag   :: Integer, 
             eps     :: Float64,
             fk      :: Array{ComplexF64} 
             [, opts :: nufft_opts]
            ) -> Array{ComplexF64}

Compute type-2 3D complex nonuniform FFT. 
"""
function nufft3d2(xj      :: Array{Float64}, 
                  yj      :: Array{Float64},
                  zj      :: Array{Float64}, 
                  iflag   :: Integer, 
                  eps     :: Float64,
                  fk      :: Array{ComplexF64},
                  opts    :: nufft_opts = finufft_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==3 || ndim==4
    if ndim==3
       ntrans = 1
    else
       ms, mt, mu, ntrans = size(fk)
    end
    cj = Array{ComplexF64}(undef, nj, ntrans)
    nufft3d2!(xj, yj, zj, cj, iflag, eps, fk, opts)
    return cj
end


## Type-3

"""
    nufft1d3(xj      :: Array{Float64}, 
             cj      :: Array{ComplexF64}, 
             iflag   :: Integer, 
             eps     :: Float64,
             sk      :: Array{Float64},
             [, opts :: nufft_opts]
            ) -> Array{ComplexF64}

Compute type-3 1D complex nonuniform FFT.
"""
function nufft1d3(xj      :: Array{Float64}, 
                  cj      :: Array{ComplexF64}, 
                  iflag   :: Integer, 
                  eps     :: Float64,
                  sk      :: Array{Float64},
                  opts    :: nufft_opts = finufft_default_opts())
    ntrans = convert(Int64, round(length(cj)/length(xj), digits=0))
    nj = length(xj)
    @assert length(cj)==nj*ntrans
    nk = length(sk)
    fk = Array{ComplexF64}(undef, nk, ntrans)
    nufft1d3!(xj, cj, iflag, eps, sk, fk, opts);
    return fk
end

"""
    nufft2d3(xj      :: Array{Float64}, 
             yj      :: Array{Float64},
             cj      :: Array{ComplexF64}, 
             iflag   :: Integer, 
             eps     :: Float64,
             sk      :: Array{Float64},
             tk      :: Array{Float64}
             [, opts :: nufft_opts]
            ) -> Array{ComplexF64}

Compute type-3 2D complex nonuniform FFT.
"""
function nufft2d3(xj      :: Array{Float64},
                  yj      :: Array{Float64}, 
                  cj      :: Array{ComplexF64}, 
                  iflag   :: Integer, 
                  eps     :: Float64,
                  sk      :: Array{Float64},
                  tk      :: Array{Float64},                  
                  opts    :: nufft_opts = finufft_default_opts())
    ntrans = convert(Int64, round(length(cj)/length(xj), digits=0))
    nj = length(xj)
    @assert length(cj)==nj*ntrans
    nk = length(sk)
    fk = Array{ComplexF64}(undef, nk, ntrans)
    nufft2d3!(xj, yj, cj, iflag, eps, sk, tk, fk, opts);
    return fk
end

"""
    nufft3d3(xj      :: Array{Float64}, 
             yj      :: Array{Float64},
             zj      :: Array{Float64},
             cj      :: Array{ComplexF64}, 
             iflag   :: Integer, 
             eps     :: Float64,
             sk      :: Array{Float64},
             tk      :: Array{Float64}
             uk      :: Array{Float64}
             [, opts :: nufft_opts]
            ) -> Array{ComplexF64}

Compute type-3 3D complex nonuniform FFT.
"""
function nufft3d3(xj      :: Array{Float64},
                  yj      :: Array{Float64},
                  zj      :: Array{Float64},                   
                  cj      :: Array{ComplexF64}, 
                  iflag   :: Integer, 
                  eps     :: Float64,
                  sk      :: Array{Float64},
                  tk      :: Array{Float64},
                  uk      :: Array{Float64},                  
                  opts    :: nufft_opts = finufft_default_opts())
    ntrans = convert(Int64, round(length(cj)/length(xj), digits=0))
    nj = length(xj)
    @assert length(cj)==nj*ntrans
    nk = length(sk)
    fk = Array{ComplexF64}(undef, nk, ntrans)
    nufft3d3!(xj, yj, zj, cj, iflag, eps, sk, tk, uk, fk, opts);
    return fk
end


### Simple Interfaces (allocate output)
### Single precision
## Type-1

"""
    nufftf1d1(xj      :: Array{Float32}, 
              cj      :: Array{ComplexF32}, 
              iflag   :: Integer, 
              eps     :: Float32,
              ms      :: Integer
              [, opts :: nufft_opts]
             ) -> Array{ComplexF32}

Compute type-1 1D complex nonuniform FFT. 
"""
function nufftf1d1(xj::Array{Float32},
                   cj::Array{ComplexF32},
                   iflag::Integer,
                   eps::Float32,
                   ms::Integer,
                   opts::nufft_opts=finufftf_default_opts())
    ntrans = convert(Int64, round(length(cj)/length(xj), digits=0))
    fk = Array{ComplexF32}(undef, ms, ntrans)
    nufftf1d1!(xj, cj, iflag, eps, fk, opts)
    return fk
end

"""
    nufftf2d1(xj      :: Array{Float32}, 
              yj      :: Array{Float32}, 
              cj      :: Array{ComplexF32}, 
              iflag   :: Integer, 
              eps     :: Float32,
              ms      :: Integer,
              mt      :: Integer,
              [, opts :: nufft_opts]
             ) -> Array{ComplexF32}

Compute type-1 2D complex nonuniform FFT.
"""
function nufftf2d1(xj      :: Array{Float32}, 
                   yj      :: Array{Float32}, 
                   cj      :: Array{ComplexF32}, 
                   iflag   :: Integer, 
                   eps     :: Float32,
                   ms      :: Integer,
                   mt      :: Integer,                   
                   opts    :: nufft_opts = finufftf_default_opts())
    ntrans = convert(Int64, round(length(cj)/length(xj), digits=0))
    fk = Array{ComplexF32}(undef, ms, mt, ntrans)
    nufftf2d1!(xj, yj, cj, iflag, eps, fk, opts)
    return fk
end

"""
    nufftf3d1(xj      :: Array{Float32}, 
              yj      :: Array{Float32}, 
              zj      :: Array{Float32}, 
              cj      :: Array{ComplexF32}, 
              iflag   :: Integer, 
              eps     :: Float32,
              ms      :: Integer,
              mt      :: Integer,
              mu      :: Integer,
              [, opts :: nufft_opts]
             ) -> Array{ComplexF32}

Compute type-1 3D complex nonuniform FFT.
"""
function nufftf3d1(xj      :: Array{Float32}, 
                   yj      :: Array{Float32},
                   zj      :: Array{Float32},                   
                   cj      :: Array{ComplexF32}, 
                   iflag   :: Integer, 
                   eps     :: Float32,
                   ms      :: Integer,
                   mt      :: Integer,
                   mu      :: Integer,                                     
                   opts    :: nufft_opts = finufftf_default_opts())
    ntrans = convert(Int64, round(length(cj)/length(xj), digits=0))
    fk = Array{ComplexF32}(undef, ms, mt, mu, ntrans)
    nufftf3d1!(xj, yj, zj, cj, iflag, eps, fk, opts)
    return fk
end


## Type-2

"""
    nufftf1d2(xj      :: Array{Float32}, 
              iflag   :: Integer, 
              eps     :: Float32,
              fk      :: Array{ComplexF32} 
              [, opts :: nufft_opts]
             ) -> Array{ComplexF32}

Compute type-2 1D complex nonuniform FFT. 
"""
function nufftf1d2(xj      :: Array{Float32},                    
                   iflag   :: Integer, 
                   eps     :: Float32,
                   fk      :: Array{ComplexF32},
                   opts    :: nufft_opts = finufftf_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==1 || ndim==2
    if ndim==1
       ntrans = 1
    else
       ms, ntrans = size(fk)
    end
    cj = Array{ComplexF32}(undef, nj, ntrans)
    nufftf1d2!(xj, cj, iflag, eps, fk, opts)
    return cj
end

"""
    nufftf2d2(xj      :: Array{Float32}, 
              yj      :: Array{Float32}, 
              iflag   :: Integer, 
              eps     :: Float32,
              fk      :: Array{ComplexF32} 
              [, opts :: nufft_opts]
             ) -> Array{ComplexF32}

Compute type-2 2D complex nonuniform FFT. 
"""
function nufftf2d2(xj      :: Array{Float32}, 
                   yj      :: Array{Float32}, 
                   iflag   :: Integer, 
                   eps     :: Float32,
                   fk      :: Array{ComplexF32},
                   opts    :: nufft_opts = finufftf_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==2 || ndim==3
    if ndim==2
       ntrans = 1
    else
       ms, mt, ntrans = size(fk)
    end
    cj = Array{ComplexF32}(undef, nj, ntrans)
    nufftf2d2!(xj, yj, cj, iflag, eps, fk, opts)
    return cj
end

"""
    nufftf3d2(xj      :: Array{Float32}, 
              yj      :: Array{Float32}, 
              zj      :: Array{Float32}, 
              iflag   :: Integer, 
              eps     :: Float32,
              fk      :: Array{ComplexF32} 
              [, opts :: nufft_opts]
             ) -> Array{ComplexF32}

Compute type-2 3D complex nonuniform FFT. 
"""
function nufftf3d2(xj      :: Array{Float32}, 
                   yj      :: Array{Float32},
                   zj      :: Array{Float32}, 
                   iflag   :: Integer, 
                   eps     :: Float32,
                   fk      :: Array{ComplexF32},
                   opts    :: nufft_opts = finufftf_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==3 || ndim==4
    if ndim==3
       ntrans = 1
    else
       ms, mt, mu, ntrans = size(fk)
    end
    cj = Array{ComplexF32}(undef, nj, ntrans)
    nufftf3d2!(xj, yj, zj, cj, iflag, eps, fk, opts)
    return cj
end


## Type-3

"""
    nufftf1d3(xj      :: Array{Float32}, 
              cj      :: Array{ComplexF32}, 
              iflag   :: Integer, 
              eps     :: Float32,
              sk      :: Array{Float32},
              [, opts :: nufft_opts]
             ) -> Array{ComplexF32}

Compute type-3 1D complex nonuniform FFT.
"""
function nufftf1d3(xj      :: Array{Float32}, 
                   cj      :: Array{ComplexF32}, 
                   iflag   :: Integer, 
                   eps     :: Float32,
                   sk      :: Array{Float32},
                   opts    :: nufft_opts = finufftf_default_opts())
    ntrans = convert(Int64, round(length(cj)/length(xj), digits=0))
    nj = length(xj)
    @assert length(cj)==nj*ntrans
    nk = length(sk)
    fk = Array{ComplexF32}(undef, nk, ntrans)
    nufftf1d3!(xj, cj, iflag, eps, sk, fk, opts);
    return fk
end

"""
    nufftf2d3(xj      :: Array{Float32}, 
              yj      :: Array{Float32},
              cj      :: Array{ComplexF32}, 
              iflag   :: Integer, 
              eps     :: Float32,
              sk      :: Array{Float32},
              tk      :: Array{Float32}
              [, opts :: nufft_opts]
             ) -> Array{ComplexF32}

Compute type-3 2D complex nonuniform FFT.
"""
function nufftf2d3(xj      :: Array{Float32},
                   yj      :: Array{Float32}, 
                   cj      :: Array{ComplexF32}, 
                   iflag   :: Integer, 
                   eps     :: Float32,
                   sk      :: Array{Float32},
                   tk      :: Array{Float32},                  
                   opts    :: nufft_opts = finufftf_default_opts())
    ntrans = convert(Int64, round(length(cj)/length(xj), digits=0))
    nj = length(xj)
    @assert length(cj)==nj*ntrans
    nk = length(sk)
    fk = Array{ComplexF32}(undef, nk, ntrans)
    nufftf2d3!(xj, yj, cj, iflag, eps, sk, tk, fk, opts);
    return fk
end

"""
    nufftf3d3(xj      :: Array{Float32}, 
              yj      :: Array{Float32},
              zj      :: Array{Float32},
              cj      :: Array{ComplexF32}, 
              iflag   :: Integer, 
              eps     :: Float32,
              sk      :: Array{Float32},
              tk      :: Array{Float32}
              uk      :: Array{Float32}
              [, opts :: nufft_opts]
             ) -> Array{ComplexF32}

Compute type-3 3D complex nonuniform FFT.
"""
function nufftf3d3(xj      :: Array{Float32},
                   yj      :: Array{Float32},
                   zj      :: Array{Float32},                   
                   cj      :: Array{ComplexF32}, 
                   iflag   :: Integer, 
                   eps     :: Float32,
                   sk      :: Array{Float32},
                   tk      :: Array{Float32},
                   uk      :: Array{Float32},                  
                   opts    :: nufft_opts = finufftf_default_opts())
    ntrans = convert(Int64, round(length(cj)/length(xj), digits=0))
    nj = length(xj)
    @assert length(cj)==nj*ntrans
    nk = length(sk)
    fk = Array{ComplexF32}(undef, nk, ntrans)
    nufftf3d3!(xj, yj, zj, cj, iflag, eps, sk, tk, uk, fk, opts);
    return fk
end


### Direct interfaces (No allocation)
### Double precision
## 1D

"""
    nufft1d1!(xj      :: Array{Float64}, 
              cj      :: Array{ComplexF64}, 
              iflag   :: Integer, 
              eps     :: Float64,
              fk      :: Array{ComplexF64} 
              [, opts :: nufft_opts]
            )

Compute type-1 1D complex nonuniform FFT. Output stored in fk.
"""
function nufft1d1!(xj      :: Array{Float64}, 
                   cj      :: Array{ComplexF64}, 
                   iflag   :: Integer, 
                   eps     :: Float64,
                   fk      :: Array{ComplexF64},
                   opts    :: nufft_opts = finufft_default_opts())
    nj = length(xj) 
    ndim = ndims(fk)
    @assert ndim==1 || ndim==2
    if ndim==1
        ntrans = 1
        ms = length(fk)
    else
        ms, ntrans = size(fk)
    end
    @assert length(cj)==nj*ntrans
    # Calling interface
    # int finufft1d1(BIGINT nj,FLT* xj,CPX* cj,int iflag,FLT eps,BIGINT ms,
    # 	       CPX* fk, nufft_opts* opts);
    # or
    # int finufft1d1many(int ntrans, BIGINT nj,FLT* xj,CPX* cj,int iflag,FLT eps,BIGINT ms,
    # 	       CPX* fk, nufft_opts* opts);
    if ndim==1
        ret = ccall( (:finufft1d1, libfinufft),
                     Cint,
                     (BIGINT,
                      Ref{Cdouble},
                      Ref{ComplexF64},
                      Cint,
                      Cdouble,
                      BIGINT,
                      Ref{ComplexF64},
                      Ref{nufft_opts}),
                     nj, xj, cj, iflag, eps, ms, fk, opts
                     )
    else
        ret = ccall( (:finufft1d1many, libfinufft),
                     Cint,
                     (Cint,
                      BIGINT,
                      Ref{Cdouble},
                      Ref{ComplexF64},
                      Cint,
                      Cdouble,
                      BIGINT,
                      Ref{ComplexF64},
                      Ref{nufft_opts}),
                     ntrans, nj, xj, cj, iflag, eps, ms, fk, opts
                     )
    end
    check_ret(ret)
end


"""
    nufft1d2!(xj      :: Array{Float64}, 
              cj      :: Array{ComplexF64}, 
              iflag   :: Integer, 
              eps     :: Float64,
              fk      :: Array{ComplexF64} 
              [, opts :: nufft_opts]
            )

Compute type-2 1D complex nonuniform FFT. Output stored in cj.
"""
function nufft1d2!(xj      :: Array{Float64}, 
                   cj      :: Array{ComplexF64}, 
                   iflag   :: Integer, 
                   eps     :: Float64,
                   fk      :: Array{ComplexF64},
                   opts    :: nufft_opts = finufft_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==1 || ndim==2
    if ndim==1
        ntrans = 1
        ms = length(fk) 
    else
        ms, ntrans = size(fk)
    end
    @assert length(cj)==nj*ntrans
    # Calling interface
    # int finufft1d2(BIGINT nj,FLT* xj,CPX* cj,int iflag,FLT eps,BIGINT ms,
    #                CPX* fk, nufft_opts* opts);
    # or
    # int finufft1d2many(int ntrans, BIGINT nj,FLT* xj,CPX* cj,int iflag,FLT eps,BIGINT ms,
    #                CPX* fk, nufft_opts* opts);
    if ntrans==1
        ret = ccall( (:finufft1d2, libfinufft),
                     Cint,
                     (BIGINT,
                      Ref{Cdouble},
                      Ref{ComplexF64},
                      Cint,
                      Cdouble,
                      BIGINT,
                      Ref{ComplexF64},
                      Ref{nufft_opts}),
                     nj, xj, cj, iflag, eps, ms, fk, opts
                     )
    else
        ret = ccall( (:finufft1d2many, libfinufft),
                     Cint,
                     (Cint,
                      BIGINT,
                      Ref{Cdouble},
                      Ref{ComplexF64},
                      Cint,
                      Cdouble,
                      BIGINT,
                      Ref{ComplexF64},
                      Ref{nufft_opts}),
                     ntrans, nj, xj, cj, iflag, eps, ms, fk, opts
                     )
    end
    check_ret(ret)    
end


"""
    nufft1d3!(xj      :: Array{Float64}, 
              cj      :: Array{ComplexF64}, 
              iflag   :: Integer, 
              eps     :: Float64,
              sk      :: Array{Float64},
              fk      :: Array{ComplexF64},
              [, opts :: nufft_opts]
             )

Compute type-3 1D complex nonuniform FFT. Output stored in fk.
"""
function nufft1d3!(xj      :: Array{Float64}, 
                   cj      :: Array{ComplexF64}, 
                   iflag   :: Integer, 
                   eps     :: Float64,
                   sk      :: Array{Float64},
                   fk      :: Array{ComplexF64},
                   opts    :: nufft_opts = finufft_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==1 || ndim==2
    if ndim==1
        ntrans = 1
        nk = length(fk)
    else
        nk, ntrans = size(fk)
    end
    @assert length(cj)==nj*ntrans
    nk = length(sk)
    @assert length(fk)==nk*ntrans
    # Calling interface
    # int finufft1d3(BIGINT nj,FLT* x,CPX* c,int iflag,FLT eps,BIGINT nk, FLT* s, CPX* f, nufft_opts* opts);
    # or
    # int finufft1d3many(int ntrans, BIGINT nj,FLT* x,CPX* c,int iflag,FLT eps,BIGINT nk, FLT* s, CPX* f, nufft_opts* opts);
    if ntrans==1
        ret = ccall( (:finufft1d3, libfinufft),
                     Cint,
                     (BIGINT,
                      Ref{Cdouble},
                      Ref{ComplexF64},
                      Cint,
                      Cdouble,
                      BIGINT,
                      Ref{Cdouble},            
                      Ref{ComplexF64},
                      Ref{nufft_opts}),
                     nj, xj, cj, iflag, eps, nk, sk, fk, opts
                     )
    else
        ret = ccall( (:finufft1d3many, libfinufft),
                     Cint,
                     (Cint,
                      BIGINT,
                      Ref{Cdouble},
                      Ref{ComplexF64},
                      Cint,
                      Cdouble,
                      BIGINT,
                      Ref{Cdouble},            
                      Ref{ComplexF64},
                      Ref{nufft_opts}),
                     ntrans, nj, xj, cj, iflag, eps, nk, sk, fk, opts
                     )
    end
    check_ret(ret)
end


## 2D

"""
    nufft2d1!(xj      :: Array{Float64}, 
              yj      :: Array{Float64}, 
              cj      :: Array{ComplexF64}, 
              iflag   :: Integer, 
              eps     :: Float64,
              fk      :: Array{ComplexF64} 
              [, opts :: nufft_opts]
            )

Compute type-1 2D complex nonuniform FFT. Output stored in fk.
"""
function nufft2d1!(xj      :: Array{Float64}, 
                   yj      :: Array{Float64}, 
                   cj      :: Array{ComplexF64}, 
                   iflag   :: Integer, 
                   eps     :: Float64,
                   fk      :: Array{ComplexF64},
                   opts    :: nufft_opts = finufft_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==2 || ndim==3
    if ndim==2
        ntrans = 1
        ms, mt = size(fk)
    else
        ms, mt, ntrans = size(fk)
    end
    @assert length(yj)==nj
    @assert length(cj)==nj*ntrans
    # Calling interface
    # int finufft2d1(BIGINT nj,FLT* xj,FLT *yj,CPX* cj,int iflag,FLT eps,
    #                BIGINT ms, BIGINT mt, CPX* fk, nufft_opts* opts);
    # or
    # int finufft2d1many(int ntrans, BIGINT nj,FLT* xj,FLT *yj,CPX* cj,int iflag,FLT eps,
    #                BIGINT ms, BIGINT mt, CPX* fk, nufft_opts* opts);
    if ntrans==1
        ret = ccall( (:finufft2d1, libfinufft),
                     Cint,
                     (BIGINT,
                      Ref{Cdouble},
                      Ref{Cdouble},            
                      Ref{ComplexF64},
                      Cint,
                      Cdouble,
                      BIGINT,
                      BIGINT,            
                      Ref{ComplexF64},
                      Ref{nufft_opts}),
                     nj, xj, yj, cj, iflag, eps, ms, mt, fk, opts
                     )
    else
        ret = ccall( (:finufft2d1many, libfinufft),
                     Cint,
                     (Cint,
                      BIGINT,
                      Ref{Cdouble},
                      Ref{Cdouble},            
                      Ref{ComplexF64},
                      Cint,
                      Cdouble,
                      BIGINT,
                      BIGINT,            
                      Ref{ComplexF64},
                      Ref{nufft_opts}),
                     ntrans, nj, xj, yj, cj, iflag, eps, ms, mt, fk, opts
                     )
    end
    check_ret(ret)
end


"""
    nufft2d2!(xj      :: Array{Float64}, 
              yj      :: Array{Float64}, 
              cj      :: Array{ComplexF64}, 
              iflag   :: Integer, 
              eps     :: Float64,
              fk      :: Array{ComplexF64} 
              [, opts :: nufft_opts]
            )

Compute type-2 2D complex nonuniform FFT. Output stored in cj.
"""
function nufft2d2!(xj      :: Array{Float64}, 
                   yj      :: Array{Float64}, 
                   cj      :: Array{ComplexF64}, 
                   iflag   :: Integer, 
                   eps     :: Float64,
                   fk      :: Array{ComplexF64},
                   opts    :: nufft_opts = finufft_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==2 || ndim==3
    if ndim==2
        ntrans = 1
        ms, mt = size(fk)
    else
        ms, mt, ntrans =  size(fk)
    end
    @assert length(yj)==nj
    @assert length(cj)==nj*ntrans
    # Calling interface
    # int finufft2d2(BIGINT nj,FLT* xj,FLT *yj,CPX* cj,int iflag,FLT eps,
    #                BIGINT ms, BIGINT mt, CPX* fk, nufft_opts* opts);
    # or
    # int finufft2d2many(int ntrans, BIGINT nj,FLT* xj,FLT *yj,CPX* cj,int iflag,FLT eps,
    #                BIGINT ms, BIGINT mt, CPX* fk, nufft_opts* opts);
    if ntrans==1
        ret = ccall( (:finufft2d2, libfinufft),
                     Cint,
                     (BIGINT,
                      Ref{Cdouble},
                      Ref{Cdouble},            
                      Ref{ComplexF64},
                      Cint,
                      Cdouble,
                      BIGINT,
                      BIGINT,            
                      Ref{ComplexF64},
                      Ref{nufft_opts}),
                     nj, xj, yj, cj, iflag, eps, ms, mt, fk, opts
                     )
    else
        ret = ccall( (:finufft2d2many, libfinufft),
                     Cint,
                     (Cint,
                      BIGINT,
                      Ref{Cdouble},
                      Ref{Cdouble},            
                      Ref{ComplexF64},
                      Cint,
                      Cdouble,
                      BIGINT,
                      BIGINT,            
                      Ref{ComplexF64},
                      Ref{nufft_opts}),
                     ntrans, nj, xj, yj, cj, iflag, eps, ms, mt, fk, opts
                     )
    end
    check_ret(ret)
end

"""
    nufft2d3!(xj      :: Array{Float64}, 
              yj      :: Array{Float64},
              cj      :: Array{ComplexF64}, 
              iflag   :: Integer, 
              eps     :: Float64,
              sk      :: Array{Float64},
              tk      :: Array{Float64},
              fk      :: Array{ComplexF64}
              [, opts :: nufft_opts]
             )

Compute type-3 2D complex nonuniform FFT. Output stored in fk.
"""
function nufft2d3!(xj      :: Array{Float64}, 
                   yj      :: Array{Float64},
                   cj      :: Array{ComplexF64}, 
                   iflag   :: Integer, 
                   eps     :: Float64,
                   sk      :: Array{Float64},
                   tk      :: Array{Float64},
                   fk      :: Array{ComplexF64},
                   opts    :: nufft_opts = finufft_default_opts())
    nj = length(xj)
    ndim =  ndims(fk)
    @assert ndim==1 || ndim==2
    if ndim==1
        ntrans = 1
        nk = length(fk)
    else
        nk, ntrans = size(fk)
    end
    @assert length(yj)==nj
    @assert length(cj)==nj*ntrans
    nk = length(sk)
    @assert length(tk)==nk
    @assert length(fk)==nk*ntrans
    # Calling interface
    # int finufft2d3(BIGINT nj,FLT* x,FLT *y,CPX* cj,int iflag,FLT eps,BIGINT nk, FLT* s, FLT* t, CPX* fk, nufft_opts* opts);    
    # or
    # int finufft2d3many(int ntrans, BIGINT nj,FLT* x,FLT *y,CPX* cj,int iflag,FLT eps,
    #                    BIGINT nk, FLT* s, FLT* t, CPX* fk, nufft_opts* opts);    
    if ntrans==1
        ret = ccall( (:finufft2d3, libfinufft),
                     Cint,
                     (BIGINT,
                      Ref{Cdouble},
                      Ref{Cdouble},            
                      Ref{ComplexF64},
                      Cint,
                      Cdouble,
                      BIGINT,
                      Ref{Cdouble},
                      Ref{Cdouble},            
                      Ref{ComplexF64},
                      Ref{nufft_opts}),
                     nj, xj, yj, cj, iflag, eps, nk, sk, tk, fk, opts
                     )
    else
        ret = ccall( (:finufft2d3many, libfinufft),
                     Cint,
                     (Cint,
                      BIGINT,
                      Ref{Cdouble},
                      Ref{Cdouble},            
                      Ref{ComplexF64},
                      Cint,
                      Cdouble,
                      BIGINT,
                      Ref{Cdouble},
                      Ref{Cdouble},            
                      Ref{ComplexF64},
                      Ref{nufft_opts}),
                     ntrans, nj, xj, yj, cj, iflag, eps, nk, sk, tk, fk, opts
                     )
    end
    check_ret(ret)
end

## 3D

"""
    nufft3d1!(xj      :: Array{Float64}, 
              yj      :: Array{Float64}, 
              zj      :: Array{Float64}, 
              cj      :: Array{ComplexF64}, 
              iflag   :: Integer, 
              eps     :: Float64,
              fk      :: Array{ComplexF64} 
              [, opts :: nufft_opts]
            )

Compute type-1 3D complex nonuniform FFT. Output stored in fk.
"""
function nufft3d1!(xj      :: Array{Float64}, 
                   yj      :: Array{Float64}, 
                   zj      :: Array{Float64}, 
                   cj      :: Array{ComplexF64}, 
                   iflag   :: Integer, 
                   eps     :: Float64,
                   fk      :: Array{ComplexF64},
                   opts    :: nufft_opts = finufft_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==3 || ndim==4
    if ndim==3
        ntrans = 1
        ms, mt, mu = size(fk)
    else
        ms, mt, mu, ntrans = size(fk)
    end
    @assert length(yj)==nj
    @assert length(zj)==nj    
    @assert length(cj)==nj*ntrans
    # Calling interface
    # int finufft3d1(BIGINT nj,FLT* xj,FLT *yj,FLT *zj,CPX* cj,int iflag,FLT eps,
    # 	       BIGINT ms, BIGINT mt, BIGINT mu, CPX* fk, nufft_opts* opts);
    # or
    # int finufft3d1many(int ntrans, BIGINT nj,FLT* xj,FLT *yj,FLT *zj,CPX* cj,int iflag,FLT eps,
    # 	       BIGINT ms, BIGINT mt, BIGINT mu, CPX* fk, nufft_opts* opts);
    if ntrans==1
        ret = ccall( (:finufft3d1, libfinufft),
                     Cint,
                     (BIGINT,
                      Ref{Cdouble},
                      Ref{Cdouble},
                      Ref{Cdouble},
                      Ref{ComplexF64},
                      Cint,
                      Cdouble,
                      BIGINT,
                      BIGINT,
                      BIGINT,
                      Ref{ComplexF64},
                      Ref{nufft_opts}),
                     nj, xj, yj, zj, cj, iflag, eps, ms, mt, mu, fk, opts
                     )
    else
        ret = ccall( (:finufft3d1many, libfinufft),
                     Cint,
                     (Cint,
                      BIGINT,
                      Ref{Cdouble},
                      Ref{Cdouble},
                      Ref{Cdouble},
                      Ref{ComplexF64},
                      Cint,
                      Cdouble,
                      BIGINT,
                      BIGINT,
                      BIGINT,
                      Ref{ComplexF64},
                      Ref{nufft_opts}),
                     ntrans, nj, xj, yj, zj, cj, iflag, eps, ms, mt, mu, fk, opts
                     )
    end
    check_ret(ret)
end

"""
    nufft3d2!(xj      :: Array{Float64}, 
              yj      :: Array{Float64}, 
              zj      :: Array{Float64}, 
              cj      :: Array{ComplexF64}, 
              iflag   :: Integer, 
              eps     :: Float64,
              fk      :: Array{ComplexF64} 
              [, opts :: nufft_opts]
            )

Compute type-2 3D complex nonuniform FFT. Output stored in cj.
"""
function nufft3d2!(xj      :: Array{Float64}, 
                   yj      :: Array{Float64},
                   zj      :: Array{Float64},                    
                   cj      :: Array{ComplexF64}, 
                   iflag   :: Integer, 
                   eps     :: Float64,
                   fk      :: Array{ComplexF64},
                   opts    :: nufft_opts = finufft_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==3 || ndim==4
    if ndim==3
        ntrans = 1
        ms, mt, mu= size(fk)
    else
        ms, mt, mu, ntrans = size(fk)
    end
    @assert length(yj)==nj
    @assert length(zj)==nj    
    @assert length(cj)==nj*ntrans
    # Calling interface
    # int finufft3d2(BIGINT nj,FLT* xj,FLT *yj,FLT *zj,CPX* cj,int iflag,FLT eps,
    #                BIGINT ms, BIGINT mt, BIGINT mu, CPX* fk, nufft_opts* opts);
    # or
    # int finufft3d2many(int ntrans, BIGINT nj,FLT* xj,FLT *yj,FLT *zj,CPX* cj,int iflag,FLT eps,
    #                BIGINT ms, BIGINT mt, BIGINT mu, CPX* fk, nufft_opts* opts);
    if ntrans==1
        ret = ccall( (:finufft3d2, libfinufft),
                     Cint,
                     (BIGINT,
                      Ref{Cdouble},
                      Ref{Cdouble},            
                      Ref{Cdouble},            
                      Ref{ComplexF64},
                      Cint,
                      Cdouble,
                      BIGINT,
                      BIGINT,
                      BIGINT,
                      Ref{ComplexF64},
                      Ref{nufft_opts}),
                     nj, xj, yj, zj, cj, iflag, eps, ms, mt, mu, fk, opts
                     )
    else
        ret = ccall( (:finufft3d2many, libfinufft),
                     Cint,
                     (Cint,
                      BIGINT,
                      Ref{Cdouble},
                      Ref{Cdouble},            
                      Ref{Cdouble},            
                      Ref{ComplexF64},
                      Cint,
                      Cdouble,
                      BIGINT,
                      BIGINT,
                      BIGINT,
                      Ref{ComplexF64},
                      Ref{nufft_opts}),
                     ntrans, nj, xj, yj, zj, cj, iflag, eps, ms, mt, mu, fk, opts
                     )
    end
    check_ret(ret)
end

"""
    nufft3d3!(xj      :: Array{Float64}, 
              yj      :: Array{Float64},
              zj      :: Array{Float64},
              cj      :: Array{ComplexF64}, 
              iflag   :: Integer, 
              eps     :: Float64,
              sk      :: Array{Float64},
              tk      :: Array{Float64},
              uk      :: Array{Float64},
              fk      :: Array{ComplexF64}
              [, opts :: nufft_opts]
             )

Compute type-3 3D complex nonuniform FFT. Output stored in fk.
"""
function nufft3d3!(xj      :: Array{Float64}, 
                   yj      :: Array{Float64},
                   zj      :: Array{Float64},                   
                   cj      :: Array{ComplexF64}, 
                   iflag   :: Integer, 
                   eps     :: Float64,
                   sk      :: Array{Float64},
                   tk      :: Array{Float64},
                   uk      :: Array{Float64},
                   fk      :: Array{ComplexF64},
                   opts    :: nufft_opts = finufft_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==1 || ndim==2
    if ndim==1
        ntrans = 1
        nk = length(fk)
    else
        nk, ntrans = size(fk)
    end
    @assert length(yj)==nj
    @assert length(zj)==nj    
    @assert length(cj)==nj*ntrans
    nk = length(sk)
    @assert length(tk)==nk
    @assert length(uk)==nk    
    @assert length(fk)==nk*ntrans
    # Calling interface
    # int finufft3d3(BIGINT nj,FLT* x,FLT *y,FLT *z, CPX* cj,int iflag,
    #                FLT eps,BIGINT nk,FLT* s, FLT* t, FLT *u,
    #                CPX* fk, nufft_opts* opts);
    # or
    # int finufft3d3many(int ntrans, BIGINT nj,FLT* x,FLT *y,FLT *z, CPX* cj,int iflag,
    #                FLT eps,BIGINT nk,FLT* s, FLT* t, FLT *u,
    #                CPX* fk, nufft_opts* opts);
    if ntrans==1
        ret = ccall( (:finufft3d3, libfinufft),
                     Cint,
                     (BIGINT,
                      Ref{Cdouble},
                      Ref{Cdouble},
                      Ref{Cdouble},                  
                      Ref{ComplexF64},
                      Cint,
                      Cdouble,
                      BIGINT,
                      Ref{Cdouble},
                      Ref{Cdouble},
                      Ref{Cdouble},                        
                      Ref{ComplexF64},
                      Ref{nufft_opts}),
                     nj, xj, yj, zj, cj, iflag, eps, nk, sk, tk, uk, fk, opts
                     )
    else
        ret = ccall( (:finufft3d3many, libfinufft),
                     Cint,
                     (Cint,
                      BIGINT,
                      Ref{Cdouble},
                      Ref{Cdouble},
                      Ref{Cdouble},                  
                      Ref{ComplexF64},
                      Cint,
                      Cdouble,
                      BIGINT,
                      Ref{Cdouble},
                      Ref{Cdouble},
                      Ref{Cdouble},                        
                      Ref{ComplexF64},
                      Ref{nufft_opts}),
                     ntrans, nj, xj, yj, zj, cj, iflag, eps, nk, sk, tk, uk, fk, opts
                     )
    end
    check_ret(ret)
end

### Direct interfaces (No allocation)
### Single precision
## 1D

"""
    nufftf1d1!(xj      :: Array{Float32}, 
               cj      :: Array{ComplexF32}, 
               iflag   :: Integer, 
               eps     :: Float32,
               fk      :: Array{ComplexF32} 
               [, opts :: nufft_opts]
              )

Compute type-1 1D complex nonuniform FFT. Output stored in fk.
"""
function nufftf1d1!(xj      :: Array{Float32}, 
                    cj      :: Array{ComplexF32}, 
                    iflag   :: Integer, 
                    eps     :: Float32,
                    fk      :: Array{ComplexF32},
                    opts    :: nufft_opts = finufftf_default_opts())
    nj = length(xj) 
    ndim = ndims(fk)
    @assert ndim==1 || ndim==2
    if ndim==1
        ntrans = 1
        ms = length(fk)
    else
        ms, ntrans = size(fk)
    end
    @assert length(cj)==nj*ntrans
    # Calling interface
    # int finufftf1d1(BIGINT nj,FLT* xj,CPX* cj,int iflag,FLT eps,BIGINT ms,
    # 	       CPX* fk, nufft_opts* opts);
    # or
    # int finufftf1d1many(int ntrans, BIGINT nj,FLT* xj,CPX* cj,int iflag,FLT eps,BIGINT ms,
    # 	       CPX* fk, nufft_opts* opts);
    if ndim==1
        ret = ccall( (:finufftf1d1, libfinufft),
                     Cint,
                     (BIGINT,
                      Ref{Cfloat},
                      Ref{ComplexF32},
                      Cint,
                      Cfloat,
                      BIGINT,
                      Ref{ComplexF32},
                      Ref{nufft_opts}),
                     nj, xj, cj, iflag, eps, ms, fk, opts
                     )
    else
        ret = ccall( (:finufftf1d1many, libfinufft),
                     Cint,
                     (Cint,
                      BIGINT,
                      Ref{Cfloat},
                      Ref{ComplexF32},
                      Cint,
                      Cfloat,
                      BIGINT,
                      Ref{ComplexF32},
                      Ref{nufft_opts}),
                     ntrans, nj, xj, cj, iflag, eps, ms, fk, opts
                     )
    end
    check_ret(ret)
end


"""
    nufftf1d2!(xj      :: Array{Float32}, 
               cj      :: Array{ComplexF32}, 
               iflag   :: Integer, 
               eps     :: Float32,
               fk      :: Array{ComplexF32} 
               [, opts :: nufft_opts]
              )

Compute type-2 1D complex nonuniform FFT. Output stored in cj.
"""
function nufftf1d2!(xj      :: Array{Float32}, 
                    cj      :: Array{ComplexF32}, 
                    iflag   :: Integer, 
                    eps     :: Float32,
                    fk      :: Array{ComplexF32},
                    opts    :: nufft_opts = finufftf_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==1 || ndim==2
    if ndim==1
        ntrans = 1
        ms = length(fk) 
    else
        ms, ntrans = size(fk)
    end
    @assert length(cj)==nj*ntrans
    # Calling interface
    # int finufftf1d2(BIGINT nj,FLT* xj,CPX* cj,int iflag,FLT eps,BIGINT ms,
    #                CPX* fk, nufft_opts* opts);
    # or
    # int finufftf1d2many(int ntrans, BIGINT nj,FLT* xj,CPX* cj,int iflag,FLT eps,BIGINT ms,
    #                CPX* fk, nufft_opts* opts);
    if ntrans==1
        ret = ccall( (:finufftf1d2, libfinufft),
                     Cint,
                     (BIGINT,
                      Ref{Cfloat},
                      Ref{ComplexF32},
                      Cint,
                      Cfloat,
                      BIGINT,
                      Ref{ComplexF32},
                      Ref{nufft_opts}),
                     nj, xj, cj, iflag, eps, ms, fk, opts
                     )
    else
        ret = ccall( (:finufftf1d2many, libfinufft),
                     Cint,
                     (Cint,
                      BIGINT,
                      Ref{Cfloat},
                      Ref{ComplexF32},
                      Cint,
                      Cfloat,
                      BIGINT,
                      Ref{ComplexF32},
                      Ref{nufft_opts}),
                     ntrans, nj, xj, cj, iflag, eps, ms, fk, opts
                     )
    end
    check_ret(ret)    
end


"""
    nufftf1d3!(xj      :: Array{Float32}, 
               cj      :: Array{ComplexF32}, 
               iflag   :: Integer, 
               eps     :: Float32,
               sk      :: Array{Float32},
               fk      :: Array{ComplexF32},
               [, opts :: nufft_opts]
              )

Compute type-3 1D complex nonuniform FFT. Output stored in fk.
"""
function nufftf1d3!(xj      :: Array{Float32}, 
                    cj      :: Array{ComplexF32}, 
                    iflag   :: Integer, 
                    eps     :: Float32,
                    sk      :: Array{Float32},
                    fk      :: Array{ComplexF32},
                    opts    :: nufft_opts = finufftf_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==1 || ndim==2
    if ndim==1
        ntrans = 1
        nk = length(fk)
    else
        nk, ntrans = size(fk)
    end
    @assert length(cj)==nj*ntrans
    nk = length(sk)
    @assert length(fk)==nk*ntrans
    # Calling interface
    # int finufftf1d3(BIGINT nj,FLT* x,CPX* c,int iflag,FLT eps,BIGINT nk, FLT* s, CPX* f, nufft_opts* opts);
    # or
    # int finufftf1d3many(int ntrans, BIGINT nj,FLT* x,CPX* c,int iflag,FLT eps,BIGINT nk, FLT* s, CPX* f, nufft_opts* opts);
    if ntrans==1
        ret = ccall( (:finufftf1d3, libfinufft),
                     Cint,
                     (BIGINT,
                      Ref{Cfloat},
                      Ref{ComplexF32},
                      Cint,
                      Cfloat,
                      BIGINT,
                      Ref{Cfloat},            
                      Ref{ComplexF32},
                      Ref{nufft_opts}),
                     nj, xj, cj, iflag, eps, nk, sk, fk, opts
                     )
    else
        ret = ccall( (:finufftf1d3many, libfinufft),
                     Cint,
                     (Cint,
                      BIGINT,
                      Ref{Cfloat},
                      Ref{ComplexF32},
                      Cint,
                      Cfloat,
                      BIGINT,
                      Ref{Cfloat},            
                      Ref{ComplexF32},
                      Ref{nufft_opts}),
                     ntrans, nj, xj, cj, iflag, eps, nk, sk, fk, opts
                     )
    end
    check_ret(ret)
end


## 2D

"""
    nufftf2d1!(xj      :: Array{Float32}, 
               yj      :: Array{Float32}, 
               cj      :: Array{ComplexF32}, 
               iflag   :: Integer, 
               eps     :: Float32,
               fk      :: Array{ComplexF32} 
               [, opts :: nufft_opts]
             )

Compute type-1 2D complex nonuniform FFT. Output stored in fk.
"""
function nufftf2d1!(xj      :: Array{Float32}, 
                    yj      :: Array{Float32}, 
                    cj      :: Array{ComplexF32}, 
                    iflag   :: Integer, 
                    eps     :: Float32,
                    fk      :: Array{ComplexF32},
                    opts    :: nufft_opts = finufftf_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==2 || ndim==3
    if ndim==2
        ntrans = 1
        ms, mt = size(fk)
    else
        ms, mt, ntrans = size(fk)
    end
    @assert length(yj)==nj
    @assert length(cj)==nj*ntrans
    # Calling interface
    # int finufftf2d1(BIGINT nj,FLT* xj,FLT *yj,CPX* cj,int iflag,FLT eps,
    #                BIGINT ms, BIGINT mt, CPX* fk, nufft_opts* opts);
    # or
    # int finufftf2d1many(int ntrans, BIGINT nj,FLT* xj,FLT *yj,CPX* cj,int iflag,FLT eps,
    #                BIGINT ms, BIGINT mt, CPX* fk, nufft_opts* opts);
    if ntrans==1
        ret = ccall( (:finufftf2d1, libfinufft),
                     Cint,
                     (BIGINT,
                      Ref{Cfloat},
                      Ref{Cfloat},            
                      Ref{ComplexF32},
                      Cint,
                      Cfloat,
                      BIGINT,
                      BIGINT,            
                      Ref{ComplexF32},
                      Ref{nufft_opts}),
                     nj, xj, yj, cj, iflag, eps, ms, mt, fk, opts
                     )
    else
        ret = ccall( (:finufftf2d1many, libfinufft),
                     Cint,
                     (Cint,
                      BIGINT,
                      Ref{Cfloat},
                      Ref{Cfloat},            
                      Ref{ComplexF32},
                      Cint,
                      Cfloat,
                      BIGINT,
                      BIGINT,            
                      Ref{ComplexF32},
                      Ref{nufft_opts}),
                     ntrans, nj, xj, yj, cj, iflag, eps, ms, mt, fk, opts
                     )
    end
    check_ret(ret)
end


"""
    nufftf2d2!(xj      :: Array{Float32}, 
               yj      :: Array{Float32}, 
               cj      :: Array{ComplexF32}, 
               iflag   :: Integer, 
               eps     :: Float32,
               fk      :: Array{ComplexF32} 
               [, opts :: nufft_opts]
             )

Compute type-2 2D complex nonuniform FFT. Output stored in cj.
"""
function nufftf2d2!(xj      :: Array{Float32}, 
                    yj      :: Array{Float32}, 
                    cj      :: Array{ComplexF32}, 
                    iflag   :: Integer, 
                    eps     :: Float32,
                    fk      :: Array{ComplexF32},
                    opts    :: nufft_opts = finufftf_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==2 || ndim==3
    if ndim==2
        ntrans = 1
        ms, mt = size(fk)
    else
        ms, mt, ntrans =  size(fk)
    end
    @assert length(yj)==nj
    @assert length(cj)==nj*ntrans
    # Calling interface
    # int finufftf2d2(BIGINT nj,FLT* xj,FLT *yj,CPX* cj,int iflag,FLT eps,
    #                BIGINT ms, BIGINT mt, CPX* fk, nufft_opts* opts);
    # or
    # int finufftf2d2many(int ntrans, BIGINT nj,FLT* xj,FLT *yj,CPX* cj,int iflag,FLT eps,
    #                BIGINT ms, BIGINT mt, CPX* fk, nufft_opts* opts);
    if ntrans==1
        ret = ccall( (:finufftf2d2, libfinufft),
                     Cint,
                     (BIGINT,
                      Ref{Cfloat},
                      Ref{Cfloat},            
                      Ref{ComplexF32},
                      Cint,
                      Cfloat,
                      BIGINT,
                      BIGINT,            
                      Ref{ComplexF32},
                      Ref{nufft_opts}),
                     nj, xj, yj, cj, iflag, eps, ms, mt, fk, opts
                     )
    else
        ret = ccall( (:finufftf2d2many, libfinufft),
                     Cint,
                     (Cint,
                      BIGINT,
                      Ref{Cfloat},
                      Ref{Cfloat},            
                      Ref{ComplexF32},
                      Cint,
                      Cfloat,
                      BIGINT,
                      BIGINT,            
                      Ref{ComplexF32},
                      Ref{nufft_opts}),
                     ntrans, nj, xj, yj, cj, iflag, eps, ms, mt, fk, opts
                     )
    end
    check_ret(ret)
end

"""
    nufftf2d3!(xj      :: Array{Float32}, 
               yj      :: Array{Float32},
               cj      :: Array{ComplexF32}, 
               iflag   :: Integer, 
               eps     :: Float32,
               sk      :: Array{Float32},
               tk      :: Array{Float32},
               fk      :: Array{ComplexF32}
               [, opts :: nufft_opts]
              )

Compute type-3 2D complex nonuniform FFT. Output stored in fk.
"""
function nufftf2d3!(xj      :: Array{Float32}, 
                    yj      :: Array{Float32},
                    cj      :: Array{ComplexF32}, 
                    iflag   :: Integer, 
                    eps     :: Float32,
                    sk      :: Array{Float32},
                    tk      :: Array{Float32},
                    fk      :: Array{ComplexF32},
                    opts    :: nufft_opts = finufftf_default_opts())
    nj = length(xj)
    ndim =  ndims(fk)
    @assert ndim==1 || ndim==2
    if ndim==1
        ntrans = 1
        nk = length(fk)
    else
        nk, ntrans = size(fk)
    end
    @assert length(yj)==nj
    @assert length(cj)==nj*ntrans
    nk = length(sk)
    @assert length(tk)==nk
    @assert length(fk)==nk*ntrans
    # Calling interface
    # int finufftf2d3(BIGINT nj,FLT* x,FLT *y,CPX* cj,int iflag,FLT eps,BIGINT nk, FLT* s, FLT* t, CPX* fk, nufft_opts* opts);    
    # or
    # int finufftf2d3many(int ntrans, BIGINT nj,FLT* x,FLT *y,CPX* cj,int iflag,FLT eps,
    #                    BIGINT nk, FLT* s, FLT* t, CPX* fk, nufft_opts* opts);    
    if ntrans==1
        ret = ccall( (:finufftf2d3, libfinufft),
                     Cint,
                     (BIGINT,
                      Ref{Cfloat},
                      Ref{Cfloat},            
                      Ref{ComplexF32},
                      Cint,
                      Cfloat,
                      BIGINT,
                      Ref{Cfloat},
                      Ref{Cfloat},            
                      Ref{ComplexF32},
                      Ref{nufft_opts}),
                     nj, xj, yj, cj, iflag, eps, nk, sk, tk, fk, opts
                     )
    else
        ret = ccall( (:finufftf2d3many, libfinufft),
                     Cint,
                     (Cint,
                      BIGINT,
                      Ref{Cfloat},
                      Ref{Cfloat},            
                      Ref{ComplexF32},
                      Cint,
                      Cfloat,
                      BIGINT,
                      Ref{Cfloat},
                      Ref{Cfloat},            
                      Ref{ComplexF32},
                      Ref{nufft_opts}),
                     ntrans, nj, xj, yj, cj, iflag, eps, nk, sk, tk, fk, opts
                     )
    end
    check_ret(ret)
end

## 3D

"""
    nufftf3d1!(xj      :: Array{Float32}, 
               yj      :: Array{Float32}, 
               zj      :: Array{Float32}, 
               cj      :: Array{ComplexF32}, 
               iflag   :: Integer, 
               eps     :: Float32,
               fk      :: Array{ComplexF32} 
               [, opts :: nufft_opts]
             )

Compute type-1 3D complex nonuniform FFT. Output stored in fk.
"""
function nufftf3d1!(xj      :: Array{Float32}, 
                    yj      :: Array{Float32}, 
                    zj      :: Array{Float32}, 
                    cj      :: Array{ComplexF32}, 
                    iflag   :: Integer, 
                    eps     :: Float32,
                    fk      :: Array{ComplexF32},
                    opts    :: nufft_opts = finufftf_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==3 || ndim==4
    if ndim==3
        ntrans = 1
        ms, mt, mu = size(fk)
    else
        ms, mt, mu, ntrans = size(fk)
    end
    @assert length(yj)==nj
    @assert length(zj)==nj    
    @assert length(cj)==nj*ntrans
    # Calling interface
    # int finufftf3d1(BIGINT nj,FLT* xj,FLT *yj,FLT *zj,CPX* cj,int iflag,FLT eps,
    # 	       BIGINT ms, BIGINT mt, BIGINT mu, CPX* fk, nufft_opts* opts);
    # or
    # int finufftf3d1many(int ntrans, BIGINT nj,FLT* xj,FLT *yj,FLT *zj,CPX* cj,int iflag,FLT eps,
    # 	       BIGINT ms, BIGINT mt, BIGINT mu, CPX* fk, nufft_opts* opts);
    if ntrans==1
        ret = ccall( (:finufftf3d1, libfinufft),
                     Cint,
                     (BIGINT,
                      Ref{Cfloat},
                      Ref{Cfloat},
                      Ref{Cfloat},
                      Ref{ComplexF32},
                      Cint,
                      Cfloat,
                      BIGINT,
                      BIGINT,
                      BIGINT,
                      Ref{ComplexF32},
                      Ref{nufft_opts}),
                     nj, xj, yj, zj, cj, iflag, eps, ms, mt, mu, fk, opts
                     )
    else
        ret = ccall( (:finufftf3d1many, libfinufft),
                     Cint,
                     (Cint,
                      BIGINT,
                      Ref{Cfloat},
                      Ref{Cfloat},
                      Ref{Cfloat},
                      Ref{ComplexF32},
                      Cint,
                      Cfloat,
                      BIGINT,
                      BIGINT,
                      BIGINT,
                      Ref{ComplexF32},
                      Ref{nufft_opts}),
                     ntrans, nj, xj, yj, zj, cj, iflag, eps, ms, mt, mu, fk, opts
                     )
    end
    check_ret(ret)
end

"""
    nufftf3d2!(xj      :: Array{Float32}, 
               yj      :: Array{Float32}, 
               zj      :: Array{Float32}, 
               cj      :: Array{ComplexF32}, 
               iflag   :: Integer, 
               eps     :: Float32,
               fk      :: Array{ComplexF32} 
               [, opts :: nufft_opts]
             )

Compute type-2 3D complex nonuniform FFT. Output stored in cj.
"""
function nufftf3d2!(xj      :: Array{Float32}, 
                    yj      :: Array{Float32},
                    zj      :: Array{Float32},                    
                    cj      :: Array{ComplexF32}, 
                    iflag   :: Integer, 
                    eps     :: Float32,
                    fk      :: Array{ComplexF32},
                    opts    :: nufft_opts = finufftf_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==3 || ndim==4
    if ndim==3
        ntrans = 1
        ms, mt, mu= size(fk)
    else
        ms, mt, mu, ntrans = size(fk)
    end
    @assert length(yj)==nj
    @assert length(zj)==nj    
    @assert length(cj)==nj*ntrans
    # Calling interface
    # int finufftf3d2(BIGINT nj,FLT* xj,FLT *yj,FLT *zj,CPX* cj,int iflag,FLT eps,
    #                BIGINT ms, BIGINT mt, BIGINT mu, CPX* fk, nufft_opts* opts);
    # or
    # int finufftf3d2many(int ntrans, BIGINT nj,FLT* xj,FLT *yj,FLT *zj,CPX* cj,int iflag,FLT eps,
    #                BIGINT ms, BIGINT mt, BIGINT mu, CPX* fk, nufft_opts* opts);
    if ntrans==1
        ret = ccall( (:finufftf3d2, libfinufft),
                     Cint,
                     (BIGINT,
                      Ref{Cfloat},
                      Ref{Cfloat},            
                      Ref{Cfloat},            
                      Ref{ComplexF32},
                      Cint,
                      Cfloat,
                      BIGINT,
                      BIGINT,
                      BIGINT,
                      Ref{ComplexF32},
                      Ref{nufft_opts}),
                     nj, xj, yj, zj, cj, iflag, eps, ms, mt, mu, fk, opts
                     )
    else
        ret = ccall( (:finufftf3d2many, libfinufft),
                     Cint,
                     (Cint,
                      BIGINT,
                      Ref{Cfloat},
                      Ref{Cfloat},            
                      Ref{Cfloat},            
                      Ref{ComplexF32},
                      Cint,
                      Cfloat,
                      BIGINT,
                      BIGINT,
                      BIGINT,
                      Ref{ComplexF32},
                      Ref{nufft_opts}),
                     ntrans, nj, xj, yj, zj, cj, iflag, eps, ms, mt, mu, fk, opts
                     )
    end
    check_ret(ret)
end

"""
    nufftf3d3!(xj      :: Array{Float32}, 
               yj      :: Array{Float32},
               zj      :: Array{Float32},
               cj      :: Array{ComplexF32}, 
               iflag   :: Integer, 
               eps     :: Float32,
               sk      :: Array{Float32},
               tk      :: Array{Float32},
               uk      :: Array{Float32},
               fk      :: Array{ComplexF32}
               [, opts :: nufft_opts]
              )

Compute type-3 3D complex nonuniform FFT. Output stored in fk.
"""
function nufftf3d3!(xj      :: Array{Float32}, 
                    yj      :: Array{Float32},
                    zj      :: Array{Float32},                   
                    cj      :: Array{ComplexF32}, 
                    iflag   :: Integer, 
                    eps     :: Float32,
                    sk      :: Array{Float32},
                    tk      :: Array{Float32},
                    uk      :: Array{Float32},
                    fk      :: Array{ComplexF32},
                    opts    :: nufft_opts = finufftf_default_opts())
    nj = length(xj)
    ndim = ndims(fk)
    @assert ndim==1 || ndim==2
    if ndim==1
        ntrans = 1
        nk = length(fk)
    else
        nk, ntrans = size(fk)
    end
    @assert length(yj)==nj
    @assert length(zj)==nj    
    @assert length(cj)==nj*ntrans
    nk = length(sk)
    @assert length(tk)==nk
    @assert length(uk)==nk    
    @assert length(fk)==nk*ntrans
    # Calling interface
    # int finufftf3d3(BIGINT nj,FLT* x,FLT *y,FLT *z, CPX* cj,int iflag,
    #                FLT eps,BIGINT nk,FLT* s, FLT* t, FLT *u,
    #                CPX* fk, nufft_opts* opts);
    # or
    # int finufftf3d3many(int ntrans, BIGINT nj,FLT* x,FLT *y,FLT *z, CPX* cj,int iflag,
    #                FLT eps,BIGINT nk,FLT* s, FLT* t, FLT *u,
    #                CPX* fk, nufft_opts* opts);
    if ntrans==1
        ret = ccall( (:finufftf3d3, libfinufft),
                     Cint,
                     (BIGINT,
                      Ref{Cfloat},
                      Ref{Cfloat},
                      Ref{Cfloat},                  
                      Ref{ComplexF32},
                      Cint,
                      Cfloat,
                      BIGINT,
                      Ref{Cfloat},
                      Ref{Cfloat},
                      Ref{Cfloat},                        
                      Ref{ComplexF32},
                      Ref{nufft_opts}),
                     nj, xj, yj, zj, cj, iflag, eps, nk, sk, tk, uk, fk, opts
                     )
    else
        ret = ccall( (:finufftf3d3many, libfinufft),
                     Cint,
                     (Cint,
                      BIGINT,
                      Ref{Cfloat},
                      Ref{Cfloat},
                      Ref{Cfloat},                  
                      Ref{ComplexF32},
                      Cint,
                      Cfloat,
                      BIGINT,
                      Ref{Cfloat},
                      Ref{Cfloat},
                      Ref{Cfloat},                        
                      Ref{ComplexF32},
                      Ref{nufft_opts}),
                     ntrans, nj, xj, yj, zj, cj, iflag, eps, nk, sk, tk, uk, fk, opts
                     )
    end
    check_ret(ret)
end

end # module
