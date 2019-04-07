import Base.Broadcast: Broadcasted, Extruded, BroadcastStyle, ArrayStyle

BroadcastStyle(::Type{<:CuArray}) = ArrayStyle{CuArray}()

function Base.similar(bc::Broadcasted{ArrayStyle{CuArray}}, ::Type{T}) where T
    similar(CuArray{T}, axes(bc))
end


# replace base functions with libdevice alternatives
# TODO: do this with Cassette.jl

cufunc(f) = f
cufunc(::Type{T}) where T = (x...) -> T(x...) # broadcasting type ctors isn't GPU compatible

Broadcast.broadcasted(::ArrayStyle{CuArray}, f, args...) =
  Broadcasted{ArrayStyle{CuArray}}(cufunc(f), args, nothing)

libdevice = :[
  cos, cospi, sin, sinpi, tan, acos, asin, atan,
  cosh, sinh, tanh, acosh, asinh, atanh,
  log, log10, log1p, log2, logb, ilogb,
  exp, exp2, exp10, expm1, ldexp,
  erf, erfinv, erfc, erfcinv, erfcx,
  brev, clz, ffs, byte_perm, popc,
  isfinite, isinf, isnan, nearbyint,
  nextafter, signbit, copysign, abs,
  sqrt, rsqrt, cbrt, rcbrt, pow,
  ceil, floor, saturate,
  lgamma, tgamma,
  j0, j1, jn, y0, y1, yn,
  normcdf, normcdfinv, hypot,
  fma, sad, dim, mul24, mul64hi, hadd, rhadd, scalbn].args

for f in libdevice
  isdefined(Base, f) || continue
  @eval cufunc(::typeof(Base.$f)) = CUDAnative.$f
end

using MacroTools

const _cufuncs = copy(libdevice)
cufuncs() = (global _cufuncs; _cufuncs)

function replace_device(ex)
  global _cufuncs
  MacroTools.postwalk(ex) do x
    x in _cufuncs ? :(CuArrays.cufunc($x)) : x
  end
end

macro cufunc(ex)
  global _cufuncs
  def = MacroTools.splitdef(ex)
  f = def[:name]
  def[:name] = Symbol(:cu, f)
  def[:body] = replace_device(def[:body])
  push!(_cufuncs, f)
  quote
    $(esc(MacroTools.combinedef(def)))
    CuArrays.cufunc(::typeof($(esc(f)))) = $(esc(def[:name]))
  end
end
