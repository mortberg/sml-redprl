structure Dynamics : DYNAMICS =
struct
  structure Abt = Abt
  structure SmallStep = SmallStep
  structure Signature = AbtSignature

  type abt = Abt.abt
  type abs = Abt.abs
  type 'a step = 'a SmallStep.t
  type sign = Signature.sign

  structure T = Signature.Telescope
  open Abt SmallStep
  infix $ \ $#

  type 'a varenv = 'a Abt.VarCtx.dict
  type 'a metaenv = 'a Signature.Abt.MetaCtx.dict

  datatype 'a closure = <: of 'a * env
  withtype env = abs closure metaenv * symenv * abt closure varenv
  infix 2 <:

  exception Stuck of abt closure


  exception hole
  fun ?x = raise x

  fun @@ (f,x) = f x
  infix 0 @@

  fun <$> (f,x) = SmallStep.map f x
  infix <$>

  fun <#> (x,f) = SmallStep.map f x
  infix <#>

  fun >>= (x,f) = SmallStep.bind f x
  infix >>=


  local
    structure Pattern = Pattern (Abt)
    structure Unify = AbtLinearUnification (structure Abt = Abt and Pattern = Pattern)
    structure SymEnvUtil = ContextUtil (structure Ctx = SymCtx and Elem = Symbol)
    structure AbsEq = struct type t = Abt.abs val eq = Abt.eqAbs end
    open OperatorData

    fun patternFromDef (opid, arity) (def : Signature.def) : Pattern.pattern =
      let
        open Pattern infix 2 $@
        val {parameters, arguments, ...} = def
        val theta = CUST (opid, parameters, arity)
      in
        into @@ theta $@ List.map (fn (x,_) => MVAR x) arguments
      end
  in
    (* computation rules for user-defined operators *)
    fun stepCust sign (opid, arity) (cl as m <: (mrho, srho, vrho)) =
      let
        open Unify infix <*>
        val def as {definiens, ...} =
          case T.lookup sign opid of
               Signature.Decl.DEF d => d
             | _ => raise Fail "Expected DEF"
        val pat = patternFromDef (opid, arity) def
        val (srho', mrho') = unify (pat <*> m)
        val srho'' = SymEnvUtil.union (srho, srho') handle _ => raise Stuck cl
        val mrho'' =
          MetaCtx.union mrho
            (MetaCtx.map (fn e => e <: (mrho, srho, vrho)) mrho') (* todo: check this? *)
            (fn _ => raise Stuck cl)
      in
        ret @@ definiens <: (mrho'', srho'', vrho)
      end
  end

  (* second-order substitution via environments *)
  fun stepMeta x (us, ms) (cl as m <: (mrho, srho, vrho)) =
    let
      val e <: (mrho', srho', vrho') = MetaCtx.lookup mrho x
      val (vs', xs) \ m = outb e
      val srho'' = ListPair.foldlEq  (fn (u,v,r) => SymCtx.insert r u v) srho' (vs', us)
      val vrho'' = ListPair.foldlEq (fn (x,m,r) => VarCtx.insert r x (m <: (mrho', srho', vrho'))) vrho' (xs, ms)
    in
      ret @@ m <: (mrho', srho'', vrho'')
    end

  fun step sign (cl as m <: (mrho, srho, vrho)) : abt closure step =
    case out m of
         `x => ret @@ VarCtx.lookup vrho x
       | x $# (us, ms) => stepMeta x (us, ms) cl
       | theta $ args =>
           let
             fun f u = SymCtx.lookup srho u handle _ => u
             val theta' = Operator.map f theta
           in
             stepOp sign theta' args (m <: (mrho, srho, vrho))
           end
           (*
    handle _ =>
      raise Stuck @@ m <: (mrho, srho, vrho)
      *)

  (* built-in computation rules *)
  and stepOp sign theta args (cl as m <: env) =
    let
      open OperatorData CttOperatorData LevelOperatorData AtomsOperatorData SortData RecordOperatorData
    in
      case theta $ args of
           CUST (opid, params, arity) $ args =>
             stepCust sign (opid, arity) cl
         | LVL_OP LBASE $ _ => FINAL
         | LVL_OP LSUCC $ [_ \ l] => FINAL
         | LVL_OP LSUP $ [_ \ l1, _ \ l2] =>
             stepLvlSup sign (l1, l2) (m <: env)
         | LCF _ $ _ => FINAL
         | RCD (PROJ lbl) $ [_ \ rcd] =>
             stepRcdProj sign (lbl, rcd) (m <: env)
         | RCD _ $ _ => FINAL
         | REFINE _ $ _ => FINAL
         | EXTRACT tau $ [_ \ r] =>
             stepExtract sign tau r cl
         | VEC_LIT _ $ _ => FINAL
         | STR_LIT _ $ _ => FINAL
         | OP_NONE _ $ _ => FINAL
         | OP_SOME _ $ _ => FINAL
         | CTT AX $ _ => FINAL
         | CTT (EQ _) $ _ => FINAL
         | CTT (CEQUIV _) $ _ => FINAL
         | CTT (MEMBER tau) $ [_ \ x, _ \ a] =>
             ret @@ check (metactx m) (CTT (EQ tau) $ [([],[]) \ x, ([],[]) \ x, ([],[]) \ a], EXP) <: env
         | CTT (UNIV tau) $ [_ \ l] => FINAL
         | CTT (SQUASH _) $ _ => FINAL
         | CTT (ENSEMBLE _) $ _ => FINAL
         | CTT (BASE _) $ _ => FINAL
         | CTT (TOP _) $ _ => FINAL
         | CTT DFUN $ _ => FINAL
         | CTT DEP_ISECT $ _ => FINAL
         | CTT FUN $ [_ \ a, _ \ b] =>
             ret @@ check (metactx m) (CTT DFUN $ [([],[]) \ a, ([],[Variable.named "x"]) \ b], EXP) <: env
         | CTT LAM $ _ => FINAL
         | CTT AP $ [_ \ f, _ \ x] =>
             stepAp sign (f, x) (m <: env)
         | CTT VOID $ [] => FINAL
         | CTT NOT $ [_ \ a] =>
             let
               val void = check' (CTT VOID $ [], EXP)
             in
               ret @@ check (metactx m) (CTT FUN $ [([],[]) \ a, ([],[]) \ void], EXP) <: env
             end
         | CTT DFUN_DOM $ [_ \ dfun] =>
             stepDFunDom sign dfun (m <: env)
         | CTT DFUN_COD $ [_ \ dfun, _ \ n] =>
             stepDFunCod sign (dfun, n) (m <: env)
         | CTT UNIV_GET_LVL $ [_ \ univ] =>
             stepUnivGetLvl sign univ (m <: env)
         | ATM (ATOM _) $ _ => FINAL
         | ATM (TOKEN _) $ _ => FINAL
         | ATM (TEST (sigma,tau)) $ [_ \ tok1, _ \ tok2, _ \ yes, _ \ no] =>
             stepAtomTest sign (sigma, tau) (tok1, tok2) (yes, no) (m <: env)
         | _ => ?hole
    end

  and stepAp sign (f, n) (m <: env) =
    let
      open OperatorData CttOperatorData SortData
    in
      ret
        (case step sign (f <: env) of
             FINAL =>
               (case out f of
                     CTT LAM $ [(_,[x]) \ e] =>
                       let
                         val (mrho, srho, vrho) = env
                       in
                         e <: (mrho, srho, VarCtx.insert vrho x (n <: env))
                       end
                   | _ => raise Stuck (m <: env))
           | STEP (f' <: env) =>
               check (metactx m) (CTT AP $ [([],[]) \ f', ([],[]) \ n], EXP) <: env)
    end

  and stepDFunDom sign dfun (m <: env) =
    let
      open OperatorData CttOperatorData SortData
    in
      ret
        (case step sign (dfun <: env) of
              FINAL =>
                (case out dfun of
                      CTT DFUN $ [_ \ a, _] =>
                        a <: env
                    | _ => raise Stuck (m <: env))
            | STEP (dfun' <: env) =>
                check (metactx m) (CTT DFUN_DOM $ [([],[]) \ dfun'], EXP) <: env)
    end

  and stepDFunCod sign (dfun, n) (m <: env) =
    let
      open OperatorData CttOperatorData SortData
    in
      ret
        (case step sign (dfun <: env) of
              FINAL =>
                (case out dfun of
                      CTT DFUN $ [_ \ _, (_, [x]) \ bx] =>
                        let
                          val (mrho, srho, vrho) = env
                        in
                          bx <: (mrho, srho, VarCtx.insert vrho x (n <: env))
                        end
                    | _ => raise Stuck (m <: env))
            | STEP (dfun' <: env) =>
                check (metactx m) (CTT DFUN_COD $ [([],[]) \ dfun', ([],[]) \ n], EXP) <: env)
    end

  and stepUnivGetLvl sign univ (m <: env) =
    let
      open OperatorData CttOperatorData SortData
    in
      ret
        (case step sign (univ <: env) of
              FINAL =>
                (case out univ of
                      CTT (UNIV tau) $ [_ \ lvl] =>
                        lvl <: env
                    | _ => raise Stuck (m <: env))
            | STEP (univ' <: env) =>
                check (metactx m) (CTT UNIV_GET_LVL $ [([],[]) \ univ'], LVL) <: env)
    end

  and stepLvlSup sign (l1, l2) (m <: env) =
    let
      open OperatorData LevelOperatorData SortData
      fun makeSup x y =
        check (metactx m) (LVL_OP LSUP $ [([],[]) \ x, ([],[]) \ y], LVL)
      fun makeSucc x =
        check (metactx m) (LVL_OP LSUCC $ [([],[]) \ x], LVL)
    in
      case step sign (l1 <: env) of
           FINAL =>
             (case step sign (l2 <: env) of
                   FINAL =>
                     (case (out l1, out l2) of
                           (LVL_OP LSUCC $ _, LVL_OP LBASE $ _) => ret @@ l1 <: env
                         | (LVL_OP LSUCC $ [_ \ l3], LVL_OP LSUCC $ [_ \ l4]) => ret @@ makeSucc (makeSup l3 l4) <: env
                         | (LVL_OP LBASE $ _, LVL_OP LBASE $ _) => ret @@ l1 <: env
                         | (LVL_OP LBASE $ _, LVL_OP LSUCC $ _) => ret @@ l2 <: env
                         | _ => raise Stuck (m <: env))
                 | STEP (l2' <: env) => ret @@ makeSup l1 l2' <: env)
         | STEP (l1' <: env) => ret @@ makeSup l1' l2 <: env
    end

  and stepRcdProj sign (lbl, rcd) (m <: env) =
    let
      open OperatorData RecordOperatorData SortData
    in
      (case step sign (rcd <: env) of
           FINAL =>
             (case out rcd of
                   RCD (CONS lbl') $ [_ \ hd, _ \ tl] =>
                       if Symbol.eq (lbl, lbl') then
                         ret @@ hd <: env
                       else
                         ret @@ check (metactx m) (RCD (PROJ lbl) $ [([],[]) \ tl], EXP) <: env
                 | _ => raise Stuck @@ m <: env)
         | STEP (rcd' <: env) =>
             ret @@ check (metactx m) (RCD (PROJ lbl) $ [([],[]) \ rcd'], EXP) <: env)
    end

  and stepAtomTest sign (sigma,tau) (tok1, tok2) (yes, no) (m <: env) =
    let
      open OperatorData AtomsOperatorData SortData
      val psi = metactx m

      fun makeTest (a,b) =
        check psi
          (ATM (TEST (sigma,tau)) $
             [([],[]) \ a,
              ([],[]) \ b,
              ([],[]) \ yes,
              ([],[]) \ no],
           tau)

      fun destToken m =
        case out m of
             ATM (TOKEN (u, tau)) $ [] => (u, tau)
           | _ => raise Stuck (m <: env)
    in
      case step sign (tok1 <: env) of
           FINAL =>
             (case step sign (tok2 <: env) of
                   FINAL =>
                     let
                       val (u1, _) = destToken tok1
                       val (u2, _) = destToken tok2
                     in
                       ret @@ (if Symbol.eq (u1, u2) then yes else no) <: env
                     end
                 | STEP (tok2' <: env) =>
                     ret @@ makeTest (tok1, tok2') <: env)
         | STEP (tok1' <: env) =>
             ret @@ makeTest (tok1', tok2) <: env
    end

  and stepExtract sign tau r (m <: env) =
    let
      open OperatorData SortData
      val psi = metactx m
    in
      case step sign (r <: env) of
           FINAL =>
             (case out r of
                  REFINE _ $ [_,_,_\evd] =>
                    (case out evd of
                          OP_SOME _ $ [_ \ evd] => ret @@ evd <: env
                        | _ => raise Stuck (evd <: env))
                | _ => raise Stuck (r <: env))
         | STEP (r' <: env) =>
             ret @@ check psi (EXTRACT tau $ [([],[]) \ r'], tau) <: env
    end
end
