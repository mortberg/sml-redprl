signature REDPRL_LEVEL =
sig
  type level
  type t = level

  type term

  val const : IntInf.int -> level (* the input must >= 0 *)
  val zero : level
  val plus : level * IntInf.int -> level (* the second argument must >= 0 *)
  val max : level list -> level
  val omega : level

  val <= : level * level -> bool
  val < : level * level -> bool
  val eq : level * level -> bool

  val top : level
  val residual : level * level -> level option

  val pretty : level -> Fpp.doc

  val into : level -> term
  val out : term -> level
end
