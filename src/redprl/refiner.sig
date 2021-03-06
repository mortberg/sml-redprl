signature REFINER =
sig
  type sign
  type abt
  type catjdg
  type rule
  type tactic
  type hyp
  type opid
  type 'a bview

  val Cut : catjdg -> rule
  val CutLemma : sign -> opid -> rule

  val AutoStep : sign -> tactic
  val Elim : sign -> hyp -> tactic
  val Exact : abt -> tactic
  val Rewrite : sign -> hyp RedPrlOpData.selector -> abt -> rule
  val RewriteHyp : sign -> hyp RedPrlOpData.selector -> hyp -> tactic
  val Symmetry : tactic
  val SynthFromHyp : hyp -> tactic

  val Inversion : hyp -> tactic

  structure Custom :
  sig
    val UnfoldAll : sign -> opid list -> rule
    val Unfold : sign -> opid list -> hyp RedPrlOpData.selector list -> rule
  end

  structure Computation :
  sig
    val ReduceAll : sign -> tactic
    val Reduce : sign -> hyp RedPrlOpData.selector list -> rule
  end

  structure Hyp :
  sig
    val Project : hyp -> rule
    val Rename : hyp -> rule
    val Delete : hyp -> rule
  end

  structure Tactical :
  sig
    val NormalizeGoalDelegate : (abt -> tactic) -> sign -> tactic
    val NormalizeHypDelegate : (abt -> hyp -> tactic) -> sign -> hyp -> tactic
  end

  type rule_name = string
  val lookupRule : rule_name -> tactic
end
