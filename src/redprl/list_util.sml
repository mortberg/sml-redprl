structure ListUtil =
struct
  local
    fun findIndex' p i : 'a list -> (int * 'a) option =
      fn [] => NONE
       | x :: l =>
           if p x then SOME (i, x)
           else findIndex' p (i+1) l
  in
    fun findIndex p l = findIndex' p 0 l
    fun findEqIndex x l = findIndex (fn y => x = y) l
  end

  fun joinWith (f : 'a -> string) (sep : string) : 'a list -> string =
    let
      fun go [] = ""
        | go (x :: []) = f x
        | go (x :: xs) = f x ^ sep ^ go xs
    in
      go
    end
  
  fun mapWithIndex f = 
    let
      fun go i [] = []
        | go i (x :: xs) = f (i, x) :: go (i + 1) xs
    in
      go 0
    end

  (* From MLton: https://github.com/MLton/mlton/blob/master/lib/mlton/basic/list.sml *)
  fun splitAt (xs, i) = 
    let
      val rec loop = 
        fn (0, acc, xs) => (rev acc, xs)
         | (_, _, []) => raise Fail "ListUtil.splitAt"
         | (i, acc, x::xs) => loop (i - 1, x :: acc, xs)
    in
      loop (i, [], xs)
    end

  local
    fun init' l [] = raise List.Empty
      | init' l [_] = List.rev l
      | init' l (x :: xs) = init' (x :: l) xs
  in
    fun init l = init' [] l
  end
end

structure ListPairUtil =
struct
  fun mapPartialEq f =
    ListPair.foldrEq
      (fn (x1, x2, ys) =>
        case f (x1, x2) of
          NONE => ys
        | SOME y => y :: ys)
      []
end
