{-# LANGUAGE OverloadedStrings #-}
module Document.Tests.TrainStation where

    -- Modules
import Document.Document as Doc

import Logic.Expr
import Logic.Proof
import Logic.Theory

import UnitB.AST
import UnitB.PO

import Theories.SetTheory
import Theories.FunctionTheory
import Theories.Arithmetic

import Z3.Z3 hiding ( verify )

    -- Libraries
import Control.Exception ( SomeException, handle )

import           Data.List ( intercalate )
import           Data.Map hiding ( map )
import qualified Data.Set as S

import Tests.UnitTest

import Utilities.Format
import Utilities.Syntactic

test_case :: TestCase
test_case = Case "train station example" test True

test :: IO Bool
test = test_cases
            [ Case "part 0" part0 True
            , Case "part 1" part1 True
            , Case "part 2" part2 True
            , Case "part 3" part3 True
            , Case "part 4" part4 True
            , Case "part 5" part5 True
            ]
part0 :: IO Bool
part0 = test_cases
            [ (Case "test 0, syntax" case0 $ Right [machine0])
            ]
part1 :: IO Bool
part1 = test_cases
            [ (POCase "test 1, verification" case1 result1)
            , (StringCase "test 2, proof obligation, INIT/fis, in" case2 result2)
            , (StringCase "test 20, proof obligation, INIT/fis, loc" case20 result20)
            , (StringCase "test 3, proof obligation, leave/fis, in'" case3 result3)
            , (StringCase "test 19, proof obligation, leave/fis, loc'" case19 result19)
            , (StringCase "test 4, proof obligation, leave/sch" case4 result4)
            ]
part2 :: IO Bool
part2 = test_cases
            [ (StringCase "test 5, proof obligation, leave/en/tr0" case5 result5)
            , (Case "test 7, undeclared symbol" case7 result7)
            , (Case "test 8, undeclared event (wrt transient)" case8 result8)
            , (Case "test 9, undeclared event (wrt c sched)" case9 result9)
            ]
part3 :: IO Bool
part3 = test_cases
            [ (Case "test 10, undeclared event (wrt indices)" case10 result10)
            , (Case "test 11, undeclared event (wrt assignment)" case11 result11)
            , (StringCase "test 12, proof obligation leave/INV/inv2" case12 result12)
            ]
part4 :: IO Bool
part4 = test_cases
            [ (POCase "test 13, verification, name clash between dummy and index" case13 result13)
            , (POCase "test 14, verification, non-exhaustive case analysis" case14 result14)
            , (POCase "test 15, verification, incorrect new assumption" case15 result15)
            ]
part5 :: IO Bool
part5 = test_cases
            [ (POCase "test 16, verification, proof by parts" case16 result16)
            , (StringCase "test 17, ill-defined types" case17 result17)
            , (StringCase "test 18, assertions have type bool" case18 result18)
            ]

train_sort :: Sort
train_sort = Sort "\\TRAIN" "TRAIN" 0
train_type :: Type
train_type = Gen $ USER_DEFINED train_sort []

loc_sort :: Sort
loc_sort = Sort "\\LOC" "LOC" 0
loc_type :: Type
loc_type = Gen $ USER_DEFINED loc_sort []

blk_sort :: Sort
blk_sort = Sort "\\BLK" "BLK" 0
blk_type :: Type
blk_type = Gen $ USER_DEFINED blk_sort []

train    :: ExprP
loc_cons :: ExprP
ent      :: ExprP
ext      :: ExprP
plf      :: ExprP
train_var :: Var
loc_var   :: Var
ent_var   :: Var
ext_var   :: Var
plf_var   :: Var

(train,train_var) = (var "TRAIN" $ set_type train_type)
(loc_cons,loc_var)   = (var "LOC" $ set_type loc_type)
(ent,ent_var)   = (var "ent" $ blk_type)
(ext,ext_var)   = (var "ext" $ blk_type)
(plf,plf_var)   = (var "PLF" $ set_type blk_type)

block :: ExprP
block_var :: Var
(block, block_var) = var "BLK" $ set_type blk_type

machine0 :: Machine
machine0 = (empty_machine "train0") 
    {  theory = empty_theory 
            {  extends = fromList
                    [  ("functions", function_theory) -- train_type blk_type
                    ,  ("sets", set_theory) -- blk_type
                    ,  ("basic", basic_theory)
                    ,  ("arithmetic", arithmetic)
--                    ,  function_theory train_type loc_type
                    ]
            ,  types   = symbol_table 
                    [ train_sort
                    , loc_sort
                    , blk_sort
                    ]
            ,  dummies = symbol_table 
                            $ (map (\t -> Var t $ train_type) 
                                [ "t","t_0","t_1","t_2","t_3" ]
                               ++ map (\t -> Var t $ blk_type) 
                                [ "p","q" ])
            ,  fact    = fromList 
                    [ (label "\\BLK-def", axm7)
                    , (label "\\LOC-def", axm8) 
                    , (label "\\TRAIN-def", axm6) 
                    , (label "axm0", axm0)
                    , (label "asm2", axm2)
                    , (label "asm3", axm3) 
                    , (label "asm4", axm4) 
                    , (label "asm5", axm5) 
                    ]
            ,  consts  = fromList
                    [  ("\\TRAIN", train_var)
                    ,  ("\\LOC", loc_var)
                    ,  ("\\BLK", block_var)
                    ,  ("ent", ent_var)
                    ,  ("ext", ext_var)
                    ,  ("PLF", plf_var)
                    ]
            }
    ,  inits = fromList $ zip (map (label . ("in" ++) . show . (1 -)) [0..])
            $ map fromJust [loc `mzeq` Right zempty_fun, in_var `mzeq` Right zempty_set]
    ,  variables = symbol_table [in_decl,loc_decl]
    ,  events = fromList [(label "enter", enter_evt), (label "leave", leave_evt)]
    ,  props = props0
    }
    where
        axm0 = fromJust (block `mzeq` (zset_enum [ent,ext] `zunion` plf)) 
        axm2 = fromJust (
                    mznot (ent `mzeq` ext)
            `mzand` mznot (ent `zelem` plf)
            `mzand` mznot (ext `zelem` plf) )
        axm3 = fromJust $
            mzforall [p_decl] mztrue $ (
                        mznot (p `mzeq` ext)
                `mzeq`  (p `zelem` (zmk_set ent `zunion` plf)))
        axm4 = fromJust $
            mzforall [p_decl] mztrue $ (
                        mznot (p `mzeq` ent)
                `mzeq`  (p `zelem` (zmk_set ext `zunion` plf)))
        axm5 = fromJust $
            mzforall [p_decl] mztrue $ (
                        (mzeq p ent `mzor` mzeq p ext)
                `mzeq`  mznot (p `zelem` plf) )
      --    	\qforall{p}{}{ \neg p = ent \equiv p \in \{ext\} \bunion PLF }

props0 :: PropertySet
props0 = empty_property_set
    {  constraint = fromList 
            [   ( label "co0"
                , Co [t_decl] 
                    $ fromJust (mzimplies 
                        (mzand (mznot (t `zelem` in_var)) (t `zelem` in_var')) 
                        (mzeq  (zapply loc' t) ent)) )
            ,   ( label "co1"
                , Co [t_decl] 
                    $ fromJust (mzimplies 
                        (mzall [ (t `zelem` in_var), 
                                 (zapply loc t `mzeq` ent), 
                                 mznot (zapply loc t `zelem` plf)])
                        (mzand (t `zelem` in_var')
                               ((zapply loc' t `zelem` plf) `mzor` ((loc' `zapply` t) 
                               `mzeq` ent)))) )
            ]
        --    t \in in \land loc.t = ent  \land \neg loc.t \in PLF 
        -- \implies t \in in' \land (loc'.t \in PLF \lor loc'.t = ent)
    ,   derivation = fromList 
            [ ( label "leave/SCH/train0/1"
              , Rule (weaken (label "leave"))
                    { remove = S.singleton (label "default")
                    , add    = S.singleton (label "c0") } )
            , ( label "enter/GRD/train0/0"
              , Rule $ add_guard (label "enter") $ label "grd1" )
            , ( label "leave/GRD/train0/0"
              , Rule $ add_guard (label "leave") $ label "grd0" ) ]
    ,   transient = fromList
            [   ( label "tr0"
                , Transient
                    (symbol_table [t_decl])
                    (fromJust (t `zelem` in_var)) [label "leave"] empty_hint)
            ]
    ,  inv = fromList 
            [   (label "inv2",fromJust (zdom loc `mzeq` in_var))
            ,   (label "inv1",fromJust $ mzforall [t_decl] (zelem t in_var)
                        ((zapply loc t `zelem` block)))
            ]
    ,  proofs = fromList
            [   ( label "train0/enter/INV/inv2"
                , ByCalc $ Calc empty_ctx ztrue ztrue [] li)
            ,   ( label "train0/leave/INV/inv2"
                , ByCalc $ Calc empty_ctx ztrue ztrue [] li)
            ,   ( label "train0/INIT/INV/inv2"
                , ByCalc $ Calc empty_ctx ztrue ztrue [] li)
            ,   ( label "train0/enter/CO/co0"
                , ByCalc $ Calc empty_ctx ztrue ztrue [] li)
            ,   ( label "train0/enter/CO/co1"
                , ByCalc $ Calc empty_ctx ztrue ztrue [] li)
            ,   ( label "train0/leave/CO/co0"
                , ByCalc $ Calc empty_ctx ztrue ztrue [] li)
            ,   ( label "train0/leave/CO/co1"
                , ByCalc $ Calc empty_ctx ztrue ztrue [] li)
            ]
    ,  safety = fromList
            []
    }
    where 
        li = LI "" 0 0

enter_evt :: Event
enter_evt = empty_event
    {  indices = symbol_table [t_decl]
    ,  guards = fromList
            [  (label "grd1", fromJust $ mznot (t `zelem` in_var))
            ]
    ,  sched_ref = [add_guard (label "enter") $ label "grd1"]
    ,  actions = fromList
            [  (label "a1", BcmSuchThat vars
                    (fromJust (in_var' `mzeq` (in_var `zunion` zmk_set t))))
            ,  (label "a2", BcmSuchThat vars
                    (fromJust (loc' `mzeq` (loc `zovl` zmk_fun t ent))))
            ]
    }
    where 
        vars = S.elems $ variableSet machine0

leave_evt :: Event
leave_evt = empty_event 
    {  indices   = symbol_table [t_decl]
    ,  scheds    = insert (label "c0") (fromJust (t `zelem` in_var)) default_schedule
    ,  sched_ref = [ (weaken (label "leave"))
                     { remove = S.singleton (label "default")
                     , add    = S.singleton (label "c0") }
                   , add_guard (label "leave") $ label "grd0"
                   ]
    ,  guards = fromList
            [  (label "grd0", fromJust $ mzand 
                                    (zapply loc t `mzeq` ext) 
                                    (t `zelem` in_var) )
            ]
    ,  actions = fromList 
            [  (label "a0", BcmSuchThat vars
                    (fromJust (in_var' `mzeq` (in_var `zsetdiff` zmk_set t))))
            ,  (label "a3", BcmSuchThat vars
                    (fromJust (loc' `mzeq` (zmk_set t `zdomsubt` loc))))
            ] 
    }
    where
        vars = S.elems $ variableSet machine0

p        :: ExprP
p_decl   :: Var
t        :: ExprP
t_decl   :: Var
in_var   :: ExprP
in_var'  :: ExprP
in_decl  :: Var
loc      :: ExprP
loc'     :: ExprP
loc_decl :: Var

(p, p_decl) = var "p" blk_type
(t, t_decl) = var "t" train_type
(in_var, in_var', in_decl) = prog_var "in" (set_type train_type)
(loc, loc', loc_decl) = prog_var "loc" (fun_type train_type blk_type)

check_sat :: [String]    
check_sat = [ "(check-sat-using (or-else (then qe smt)"
            , "                          (then simplify smt)"
            , "                          (then skip smt)"
            , "                          (then (using-params simplify :expand-power true) smt)))"
            ]


train_decl :: Bool -> Bool -> [String]
train_decl b ind = 
        [ "(declare-datatypes (a) ( (Maybe (Just (fromJust a)) Nothing) ))"
        , "(declare-datatypes () ( (Null null) ))"
        , "(declare-datatypes (a b) ( (Pair (pair (first a) (second b))) ))"
        , "(declare-sort BLK 0)"
        , "; comment: we don't need to declare the sort Bool"
        , "; comment: we don't need to declare the sort Int"
        , "(declare-sort LOC 0)"
        , "; comment: we don't need to declare the sort Real"
        , "(declare-sort TRAIN 0)"
        , "(define-sort pfun (a b) (Array a (Maybe b)))"
        , "(define-sort set (a) (Array a Bool))"
        , "(declare-const PLF (set BLK))"
        , "(declare-const ent BLK)"
        , "(declare-const ext BLK)"
        ] ++ var_decl ++
        if ind then
        [
--        [ "(declare-const p BLK)"
--        , "(declare-const q BLK)"
        "(declare-const t TRAIN)"
--        , "(declare-const t_0 TRAIN)"
--        , "(declare-const t_1 TRAIN)"
--        , "(declare-const t_2 TRAIN)"
--        , "(declare-const t_3 TRAIN)"
        ] 
        else []
    where
        var_decl
            | b         =
                [  "(declare-const in (set TRAIN))"
                ,  "(declare-const in@prime (set TRAIN))"
                ,  "(declare-const loc (pfun TRAIN BLK))"
                ,  "(declare-const loc@prime (pfun TRAIN BLK))"
                ]
            | otherwise = 
                [  "(declare-const in (set TRAIN))"
                ,  "(declare-const loc (pfun TRAIN BLK))"
                ]

set_decl_smt2 :: [AxiomOption] -> [String]
set_decl_smt2 xs = 
        when (WithPFun `elem` xs)
        [ "(declare-fun apply@@TRAIN@@BLK ( (pfun TRAIN BLK) TRAIN ) BLK)"]
--        ,  "(declare-fun bunion@Open@@pfun@@TRAIN@@BLK@Close ((set (pfun TRAIN BLK)) (set (pfun TRAIN BLK))) (set (pfun TRAIN BLK)))"
     ++ when (WithPFun `elem` xs)
        [  "(declare-fun dom-rest@@TRAIN@@BLK"
        ,  "             ( (set TRAIN)"
        ,  "               (pfun TRAIN BLK) )"
        ,  "             (pfun TRAIN BLK))"
        ,  "(declare-fun dom-subt@@TRAIN@@BLK"
        ,  "             ( (set TRAIN)"
        ,  "               (pfun TRAIN BLK) )"
        ,  "             (pfun TRAIN BLK))"
        ,  "(declare-fun dom@@TRAIN@@BLK ( (pfun TRAIN BLK) ) (set TRAIN))"]
--        ,  "(declare-fun elem@Open@@pfun@@TRAIN@@BLK@Close ((pfun TRAIN BLK) (set (pfun TRAIN BLK))) Bool)"
     ++ when (WithPFun `elem` xs)
        [  "(declare-fun empty-fun@@TRAIN@@BLK () (pfun TRAIN BLK))"]
--        ,  "(declare-fun empty-set@Open@@pfun@@TRAIN@@BLK@Close () (set (pfun TRAIN BLK)))"
     ++ when (WithPFun `elem` xs)
        [  "(declare-fun injective@@TRAIN@@BLK ( (pfun TRAIN BLK) ) Bool)" ]
--        ,  "(declare-fun intersect@Open@@pfun@@TRAIN@@BLK@Close ((set (pfun TRAIN BLK)) (set (pfun TRAIN BLK))) (set (pfun TRAIN BLK)))"
     ++ when (WithPFun `elem` xs)
        [  "(declare-fun mk-fun@@TRAIN@@BLK (TRAIN BLK) (pfun TRAIN BLK))"]
     ++ [  "(declare-fun mk-set@@BLK (BLK) (set BLK))"
        ,  "(declare-fun mk-set@@TRAIN (TRAIN) (set TRAIN))"]
--        ,  "(declare-fun mk-set@Open@@pfun@@TRAIN@@BLK@Close ((pfun TRAIN BLK)) (set (pfun TRAIN BLK)))"
     ++ when (WithPFun `elem` xs)
        [ "(declare-fun ovl@@TRAIN@@BLK"
        , "             ( (pfun TRAIN BLK)"
        , "               (pfun TRAIN BLK) )"
        , "             (pfun TRAIN BLK))"
        , "(declare-fun ran@@TRAIN@@BLK ( (pfun TRAIN BLK) ) (set BLK))"]
--        ,  "(declare-fun set-diff@Open@@pfun@@TRAIN@@BLK@Close ((set (pfun TRAIN BLK)) (set (pfun TRAIN BLK))) (set (pfun TRAIN BLK)))"
     ++ when (WithPFun `elem` xs)
        [ "(declare-fun set@@TRAIN@@BLK ( (pfun TRAIN BLK) ) (set BLK))"]
     ++ [ "(define-fun BLK () (set BLK) ( (as const (set BLK)) true ))"
        , "(define-fun LOC () (set LOC) ( (as const (set LOC)) true ))"
        , "(define-fun TRAIN"
        , "            ()"
        , "            (set TRAIN)"
        , "            ( (as const (set TRAIN))"
        , "              true ))"
        , "(define-fun compl@@BLK"
        , "            ( (s1 (set BLK)) )"
        , "            (set BLK)"
        , "            ((_ map not) s1))"
        , "(define-fun compl@@TRAIN"
        , "            ( (s1 (set TRAIN)) )"
        , "            (set TRAIN)"
        , "            ((_ map not) s1))"
        , "(define-fun elem@@BLK"
        , "            ( (x BLK)"
        , "              (s1 (set BLK)) )"
        , "            Bool"
        , "            (select s1 x))"
        , "(define-fun elem@@TRAIN"
        , "            ( (x TRAIN)"
        , "              (s1 (set TRAIN)) )"
        , "            Bool"
        , "            (select s1 x))"
        , "(define-fun empty-set@@BLK"
        , "            ()"
        , "            (set BLK)"
        , "            ( (as const (set BLK))"
        , "              false ))"
        , "(define-fun empty-set@@TRAIN"
        , "            ()"
        , "            (set TRAIN)"
        , "            ( (as const (set TRAIN))"
        , "              false ))"
        , "(define-fun set-diff@@BLK"
        , "            ( (s1 (set BLK))"
        , "              (s2 (set BLK)) )"
        , "            (set BLK)"
        , "            (intersect s1 ((_ map not) s2)))"
        , "(define-fun set-diff@@TRAIN"
        , "            ( (s1 (set TRAIN))"
        , "              (s2 (set TRAIN)) )"
        , "            (set TRAIN)"
        , "            (intersect s1 ((_ map not) s2)))"
        ]
--        ,  "(declare-fun subset@Open@@pfun@@TRAIN@@BLK@Close ((set (pfun TRAIN BLK)) (set (pfun TRAIN BLK))) Bool)"
--     ++ when (WithPFun `elem` xs)
--        [  "(declare-fun tfun@@TRAIN@@BLK ((set TRAIN) (set BLK)) (set (pfun TRAIN BLK)))"]
    where
        when b xs = if b then xs else []

set_facts :: [(String,String)] -> [(String,String)]
set_facts xs = [ f x y | y <- ys, x <- xs ]
  where
    f :: (String, String) -> (String, String) -> (String, String)
    f (x0,x1) (x,y) = (format x x1, format y x0 x1)
    unlines = L.intercalate "\n"
    ys =[   ( "{0}0", unlines
                [ "(assert (forall ( (x {0})"
                , "                  (y {0}) )"
                , "                (! (= (elem@{1} x (mk-set@{1} y)) (= x y))"
                , "                   :pattern"
                , "                   ( (elem@{1} x (mk-set@{1} y)) ))))"]
            )
--            -- elem over intersection
--        Right axm2 = mzforall [x_decl,s1_decl,s2_decl] (
--                          (x `zelem` (s1 `zintersect` s2)) 
--                    `mzeq` ( (x `zelem` s1) `mzand` (x `zelem` s2) ))
--            -- elem over union
--        Right axm3 = mzforall [x_decl,s1_decl,s2_decl] (
--                          (x `zelem` (s1 `zunion` s2)) 
--                    `mzeq` ( (x `zelem` s1) `mzor` (x `zelem` s2) ))
--            -- elem over empty-set
--        Right axm4 = mzforall [x_decl,s1_decl,s2_decl] (
--                          mznot (x `zelem` Right zempty_set)  )
--        axm5 = fromJust $ mzforall [x_decl,s1_decl] mztrue (
--                          mzeq (zelem x s1)
--                               (zset_select s1 x)  )
            -- subset extensionality
--        axm6 = fromJust $ mzforall [s1_decl,s2_decl] mztrue $
--                        ( s1 `zsubset` s2 )
--                 `mzeq` (mzforall [x_decl] mztrue ( zelem x s1 `mzimplies` zelem x s2 ))
        ]



fun_facts :: (String,String) -> (String,String) -> [(String,String)]
fun_facts (x0,x1) (y0,y1) = map (\(x,y) -> (format x x1 y1, format y x0 x1 y0 y1)) $
                            zip (map (("{0}{1}" ++) . show) [0..]) 
        [ "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (f2 (pfun {0} {2})) )"
        , "                (! (= (dom@{1}@{3} (ovl@{1}@{3} f1 f2))"
        , "                      (union (dom@{1}@{3} f1) (dom@{1}@{3} f2)))"
        , "                   :pattern"
        , "                   ( (dom@{1}@{3} (ovl@{1}@{3} f1 f2)) ))))"
        , "(assert (= (dom@{1}@{3} empty-fun@{1}@{3})"
        , "           empty-set@{1}))"
        , "(assert (forall ( (x {0})"
        , "                  (y {2}) )"
        , "                (! (= (dom@{1}@{3} (mk-fun@{1}@{3} x y))"
        , "                      (mk-set@{1} x))"
        , "                   :pattern"
        , "                   ( (dom@{1}@{3} (mk-fun@{1}@{3} x y)) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (f2 (pfun {0} {2}))"
        , "                  (x {0}) )"
        , "                (! (=> (elem@{1} x (dom@{1}@{3} f2))"
        , "                       (= (apply@{1}@{3} (ovl@{1}@{3} f1 f2) x)"
        , "                          (apply@{1}@{3} f2 x)))"
        , "                   :pattern"
        , "                   ( (apply@{1}@{3} (ovl@{1}@{3} f1 f2) x) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (f2 (pfun {0} {2}))"
        , "                  (x {0}) )"
        , "                (! (=> (and (elem@{1} x (dom@{1}@{3} f1))"
        , "                            (not (elem@{1} x (dom@{1}@{3} f2))))"
        , "                       (= (apply@{1}@{3} (ovl@{1}@{3} f1 f2) x)"
        , "                          (apply@{1}@{3} f1 x)))"
        , "                   :pattern"
        , "                   ( (apply@{1}@{3} (ovl@{1}@{3} f1 f2) x) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (s1 (set {0})) )"
        , "                (! (= (dom@{1}@{3} (dom-subt@{1}@{3} s1 f1))"
        , "                      (set-diff@{1} (dom@{1}@{3} f1) s1))"
        , "                   :pattern"
        , "                   ( (dom@{1}@{3} (dom-subt@{1}@{3} s1 f1)) ))))"
        , "(assert (forall ( (x {0})"
        , "                  (y {2}) )"
        , "                (! (= (apply@{1}@{3} (mk-fun@{1}@{3} x y) x) y)"
        , "                   :pattern"
        , "                   ( (apply@{1}@{3} (mk-fun@{1}@{3} x y) x) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (s1 (set {0}))"
        , "                  (x {0}) )"
        , "                (! (=> (and (elem@{1} x s1)"
        , "                            (elem@{1} x (dom@{1}@{3} f1)))"
        , "                       (= (apply@{1}@{3} (dom-rest@{1}@{3} s1 f1) x)"
        , "                          (apply@{1}@{3} f1 x)))"
        , "                   :pattern"
        , "                   ( (apply@{1}@{3} (dom-rest@{1}@{3} s1 f1) x) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (s1 (set {0}))"
        , "                  (x {0}) )"
        , "                (! (=> (elem@{1} x (set-diff@{1} (dom@{1}@{3} f1) s1))"
        , "                       (= (apply@{1}@{3} (dom-subt@{1}@{3} s1 f1) x)"
        , "                          (apply@{1}@{3} f1 x)))"
        , "                   :pattern"
        , "                   ( (apply@{1}@{3} (dom-subt@{1}@{3} s1 f1) x) ))))"
        , "(assert (forall ( (x {0}) )"
        , "                (! (= (select empty-fun@{1}@{3} x)"
        , "                      (as Nothing (Maybe {2})))"
        , "                   :pattern"
        , "                   ( (select empty-fun@{1}@{3} x) ))))"
        , "(assert (forall ( (x {0})"
        , "                  (x2 {0})"
        , "                  (y {2}) )"
        , "                (! (= (select (mk-fun@{1}@{3} x y) x2)"
        , "                      (ite (= x x2) (Just y) (as Nothing (Maybe {2}))))"
        , "                   :pattern"
        , "                   ( (select (mk-fun@{1}@{3} x y) x2) ))))"
        , "(assert (forall ( (x {0})"
        , "                  (f1 (pfun {0} {2}))"
        , "                  (f2 (pfun {0} {2})) )"
        , "                (! (= (select (ovl@{1}@{3} f1 f2) x)"
        , "                      (ite (= (select f2 x) (as Nothing (Maybe {2})))"
        , "                           (select f1 x)"
        , "                           (select f2 x)))"
        , "                   :pattern"
        , "                   ( (select (ovl@{1}@{3} f1 f2) x) ))))"
        , "(assert (forall ( (x {0})"
        , "                  (f1 (pfun {0} {2})) )"
        , "                (! (= (select (dom@{1}@{3} f1) x)"
        , "                      (not (= (select f1 x) (as Nothing (Maybe {2})))))"
        , "                   :pattern"
        , "                   ( (select (dom@{1}@{3} f1) x) ))))"
        , "(assert (forall ( (y {2})"
        , "                  (f1 (pfun {0} {2})) )"
        , "                (! (= (elem@{3} y (set@{1}@{3} f1))"
        , "                      (exists ( (x {0}) )"
        , "                              (and (elem@{1} x (dom@{1}@{3} f1))"
        , "                                   (= (apply@{1}@{3} f1 x) y))))"
        , "                   :pattern"
        , "                   ( (elem@{3} y (set@{1}@{3} f1)) ))))"
        , "(assert (forall ( (x {0})"
        , "                  (y {2})"
        , "                  (f1 (pfun {0} {2})) )"
        , "                (! (= (and (elem@{1} x (dom@{1}@{3} f1))"
        , "                           (= (apply@{1}@{3} f1 x) y))"
        , "                      (= (select f1 x) (Just y)))"
        , "                   :pattern"
        , "                   ())))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (x2 {0})"
        , "                  (x {0})"
        , "                  (y {2}) )"
        , "                (! (=> (not (= x x2))"
        , "                       (= (apply@{1}@{3} (ovl@{1}@{3} f1 (mk-fun@{1}@{3} x y)) x2)"
        , "                          (apply@{1}@{3} f1 x2)))"
        , "                   :pattern"
        , "                   ( (apply@{1}@{3} (ovl@{1}@{3} f1 (mk-fun@{1}@{3} x y)) x2) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (x {0})"
        , "                  (y {2}) )"
        , "                (! (= (apply@{1}@{3} (ovl@{1}@{3} f1 (mk-fun@{1}@{3} x y)) x)"
        , "                      y)"
        , "                   :pattern"
        , "                   ( (apply@{1}@{3} (ovl@{1}@{3} f1 (mk-fun@{1}@{3} x y)) x) ))))"
        , "(assert (= (ran@{1}@{3} empty-fun@{1}@{3})"
        , "           empty-set@{3}))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (y {2}) )"
        , "                (! (= (elem@{3} y (ran@{1}@{3} f1))"
        , "                      (exists ( (x {0}) )"
        , "                              (and true"
        , "                                   (and (elem@{1} x (dom@{1}@{3} f1))"
        , "                                        (= (apply@{1}@{3} f1 x) y)))))"
        , "                   :pattern"
        , "                   ( (elem@{3} y (ran@{1}@{3} f1)) ))))"
        , "(assert (forall ( (x {0})"
        , "                  (y {2}) )"
        , "                (! (= (ran@{1}@{3} (mk-fun@{1}@{3} x y))"
        , "                      (mk-set@{3} y))"
        , "                   :pattern"
        , "                   ( (ran@{1}@{3} (mk-fun@{1}@{3} x y)) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (f2 (pfun {0} {2})) )"
        , "                (! (subset (ran@{1}@{3} (ovl@{1}@{3} f1 f2))"
        , "                           (union (ran@{1}@{3} f1) (ran@{1}@{3} f2)))"
        , "                   :pattern"
        , "                   ( (subset (ran@{1}@{3} (ovl@{1}@{3} f1 f2))"
        , "                             (union (ran@{1}@{3} f1) (ran@{1}@{3} f2))) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2})) )"
        , "                (! (= (injective@{1}@{3} f1)"
        , "                      (forall ( (x {0})"
        , "                                (x2 {0}) )"
        , "                              (=> (and (elem@{1} x (dom@{1}@{3} f1))"
        , "                                       (elem@{1} x2 (dom@{1}@{3} f1)))"
        , "                                  (=> (= (apply@{1}@{3} f1 x)"
        , "                                         (apply@{1}@{3} f1 x2))"
        , "                                      (= x x2)))))"
        , "                   :pattern"
        , "                   ( (injective@{1}@{3} f1) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (x {0}) )"
        , "                (! (=> (and (injective@{1}@{3} f1)"
        , "                            (elem@{1} x (dom@{1}@{3} f1)))"
        , "                       (= (ran@{1}@{3} (dom-subt@{1}@{3} (mk-set@{1} x) f1))"
        , "                          (set-diff@{3} (ran@{1}@{3} f1)"
        , "                                         (mk-set@{3} (apply@{1}@{3} f1 x)))))"
        , "                   :pattern"
        , "                   ( (ran@{1}@{3} (dom-subt@{1}@{3} (mk-set@{1} x) f1)) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (x {0})"
        , "                  (x2 {0}) )"
        , "                (! (=> (and (not (= x x2))"
        , "                            (elem@{1} x2 (dom@{1}@{3} f1)))"
        , "                       (= (apply@{1}@{3} (dom-subt@{1}@{3} (mk-set@{1} x) f1) x2)"
        , "                          (apply@{1}@{3} f1 x2)))"
        , "                   :pattern"
        , "                   ( (apply@{1}@{3} (dom-subt@{1}@{3} (mk-set@{1} x) f1) x2) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (x {0}) )"
        , "                (! (=> (elem@{1} x (dom@{1}@{3} f1))"
        , "                       (= (apply@{1}@{3} (dom-rest@{1}@{3} (mk-set@{1} x) f1) x)"
        , "                          (apply@{1}@{3} f1 x)))"
        , "                   :pattern"
        , "                   ( (apply@{1}@{3} (dom-rest@{1}@{3} (mk-set@{1} x) f1) x) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (x {0})"
        , "                  (s1 (set {0})) )"
        , "                (! (=> (and (not (elem@{1} x s1))"
        , "                            (elem@{1} x (dom@{1}@{3} f1)))"
        , "                       (= (apply@{1}@{3} (dom-subt@{1}@{3} s1 f1) x)"
        , "                          (apply@{1}@{3} f1 x)))"
        , "                   :pattern"
        , "                   ( (apply@{1}@{3} (dom-subt@{1}@{3} s1 f1) x) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (x {0})"
        , "                  (s1 (set {0})) )"
        , "                (! (=> (and (elem@{1} x s1)"
        , "                            (elem@{1} x (dom@{1}@{3} f1)))"
        , "                       (= (apply@{1}@{3} (dom-rest@{1}@{3} s1 f1) x)"
        , "                          (apply@{1}@{3} f1 x)))"
        , "                   :pattern"
        , "                   ( (apply@{1}@{3} (dom-rest@{1}@{3} s1 f1) x) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (x {0}) )"
        , "                (! (=> (elem@{1} x (dom@{1}@{3} f1))"
        , "                       (elem@{3} (apply@{1}@{3} f1 x) (ran@{1}@{3} f1)))"
        , "                   :pattern"
        , "                   ( (elem@{3} (apply@{1}@{3} f1 x) (ran@{1}@{3} f1)) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (x {0})"
        , "                  (s1 (set {0})) )"
        , "                (! (=> (elem@{1} x (set-diff@{1} (dom@{1}@{3} f1) s1))"
        , "                       (elem@{3} (apply@{1}@{3} f1 x)"
        , "                                  (ran@{1}@{3} (dom-subt@{1}@{3} s1 f1))))"
        , "                   :pattern"
        , "                   ( (elem@{3} (apply@{1}@{3} f1 x)"
        , "                                (ran@{1}@{3} (dom-subt@{1}@{3} s1 f1))) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (x {0})"
        , "                  (s1 (set {0})) )"
        , "                (! (=> (elem@{1} x (intersect (dom@{1}@{3} f1) s1))"
        , "                       (elem@{3} (apply@{1}@{3} f1 x)"
        , "                                  (ran@{1}@{3} (dom-rest@{1}@{3} s1 f1))))"
        , "                   :pattern"
        , "                   ( (elem@{3} (apply@{1}@{3} f1 x)"
        , "                                (ran@{1}@{3} (dom-rest@{1}@{3} s1 f1))) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (x {0})"
        , "                  (y {2}) )"
        , "                (! (=> (and (elem@{1} x (dom@{1}@{3} f1))"
        , "                            (injective@{1}@{3} f1))"
        , "                       (= (ran@{1}@{3} (ovl@{1}@{3} f1 (mk-fun@{1}@{3} x y)))"
        , "                          (union (set-diff@{3} (ran@{1}@{3} f1)"
        , "                                                (mk-set@{3} (apply@{1}@{3} f1 x)))"
        , "                                 (mk-set@{3} y))))"
        , "                   :pattern"
        , "                   ( (ran@{1}@{3} (ovl@{1}@{3} f1 (mk-fun@{1}@{3} x y))) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (x {0})"
        , "                  (y {2}) )"
        , "                (! (=> (not (elem@{1} x (dom@{1}@{3} f1)))"
        , "                       (= (ran@{1}@{3} (ovl@{1}@{3} f1 (mk-fun@{1}@{3} x y)))"
        , "                          (union (ran@{1}@{3} f1) (mk-set@{3} y))))"
        , "                   :pattern"
        , "                   ( (ran@{1}@{3} (ovl@{1}@{3} f1 (mk-fun@{1}@{3} x y))) ))))"
        , "(assert (forall ( (f1 (pfun {0} {2}))"
        , "                  (y {2}) )"
        , "                (! (= (= (set@{1}@{3} f1) (mk-set@{3} y))"
        , "                      (forall ( (x {0}) )"
        , "                              (=> true"
        , "                                  (or (= (select f1 x) (Just y))"
        , "                                      (= (select f1 x) (as Nothing (Maybe {2})))))))"
        , "                   :pattern"
        , "                   ())))"
        ] -- 27

data AxiomOption = WithPFun
    deriving Eq

comp_facts :: [AxiomOption] -> [String]
comp_facts xs = 
           ( map snd    (     (if (WithPFun `elem` xs) then
                               concatMap set_facts 
                                [ --  ("(pfun TRAIN BLK)", "Open@@pfun@@TRAIN@@BLK@Close")
                                ]
                            ++ concatMap (uncurry fun_facts) 
                                [  (("TRAIN","@TRAIN"),("BLK","@BLK"))
                                ] 
                               else [])
                            ++ set_facts 
                                [   ("BLK","@BLK")
                                ,   ("TRAIN","@TRAIN")
                                ] ) )
named_facts :: [String]
named_facts = []


path0 :: String
path0 = "Tests/train-station.tex"

case0 :: IO (Either [Error] [Machine])
case0 = parse_machine path0

result1 :: String
result1 = unlines 
    [ "  o  train0/INIT/FIS/in"
    , "  o  train0/INIT/FIS/loc"
    , "  o  train0/INIT/INV/inv1"
    , "  o  train0/INIT/INV/inv2/goal (422,1)"
    , "  o  train0/INIT/INV/inv2/hypotheses (422,1)"
    , "  o  train0/INIT/INV/inv2/relation (422,1)"
    , "  o  train0/INIT/INV/inv2/step (424,1)"
    , "  o  train0/INIT/INV/inv2/step (426,1)"
    , "  o  train0/INIT/INV/inv2/step (428,1)"
    , "  o  train0/INIT/WD"
    , "  o  train0/INV/WD"
    , "  o  train0/SKIP/CO/co0"
    , "  o  train0/SKIP/CO/co1"
    , "  o  train0/TR/tr0/t@param"
    , "  o  train0/co0/CO/WD"
    , "  o  train0/co1/CO/WD"
    , "  o  train0/enter/CO/co0/case 1/goal (335,1)"
    , "  o  train0/enter/CO/co0/case 1/hypotheses (335,1)"
    , "  o  train0/enter/CO/co0/case 1/relation (335,1)"
    , "  o  train0/enter/CO/co0/case 1/step (337,1)"
    , "  o  train0/enter/CO/co0/case 1/step (339,1)"
    , "  o  train0/enter/CO/co0/case 2/goal (347,1)"
    , "  o  train0/enter/CO/co0/case 2/hypotheses (347,1)"
    , "  o  train0/enter/CO/co0/case 2/relation (347,1)"
    , "  o  train0/enter/CO/co0/case 2/step (349,1)"
    , "  o  train0/enter/CO/co0/case 2/step (351,1)"
    , "  o  train0/enter/CO/co0/case 2/step (353,1)"
    , "  o  train0/enter/CO/co0/case 2/step (355,1)"
    , "  o  train0/enter/CO/co0/completeness (332,1)"
    , "  o  train0/enter/CO/co1/completeness (246,1)"
    , "  o  train0/enter/CO/co1/new assumption (223,1)"
    , "  o  train0/enter/CO/co1/part 1/goal (250,2)"
    , "  o  train0/enter/CO/co1/part 1/hypotheses (250,2)"
    , "  o  train0/enter/CO/co1/part 1/relation (250,2)"
    , "  o  train0/enter/CO/co1/part 1/step (252,2)"
    , "  o  train0/enter/CO/co1/part 1/step (254,2)"
    , "  o  train0/enter/CO/co1/part 2/case 1/goal (264,2)"
    , "  o  train0/enter/CO/co1/part 2/case 1/hypotheses (264,2)"
    , "  o  train0/enter/CO/co1/part 2/case 1/relation (264,2)"
    , "  o  train0/enter/CO/co1/part 2/case 1/step (266,2)"
    , "  o  train0/enter/CO/co1/part 2/case 1/step (268,2)"
    , "  o  train0/enter/CO/co1/part 2/case 2/assertion/hyp6/easy (288,2)"
    , "  o  train0/enter/CO/co1/part 2/case 2/main goal/goal (278,2)"
    , "  o  train0/enter/CO/co1/part 2/case 2/main goal/hypotheses (278,2)"
    , "  o  train0/enter/CO/co1/part 2/case 2/main goal/relation (278,2)"
    , "  o  train0/enter/CO/co1/part 2/case 2/main goal/step (280,2)"
    , "  o  train0/enter/CO/co1/part 2/case 2/main goal/step (282,2)"
    , "  o  train0/enter/CO/co1/part 2/case 2/main goal/step (284,2)"
    , "  o  train0/enter/CO/co1/part 2/completeness (261,2)"
    , "  o  train0/enter/FIS/in@prime"
    , "  o  train0/enter/FIS/loc@prime"
    , "  o  train0/enter/INV/inv1"
    , "  o  train0/enter/INV/inv2/goal (77,1)"
    , "  o  train0/enter/INV/inv2/hypotheses (77,1)"
    , "  o  train0/enter/INV/inv2/relation (77,1)"
    , "  o  train0/enter/INV/inv2/step (79,1)"
    , "  o  train0/enter/INV/inv2/step (81,1)"
    , "  o  train0/enter/INV/inv2/step (83,1)"
    , "  o  train0/enter/INV/inv2/step (85,1)"
    , "  o  train0/enter/INV/inv2/step (87,1)"
    , "  o  train0/enter/SCH"
    , "  o  train0/enter/WD/ACT/a1"
    , "  o  train0/enter/WD/ACT/a2"
    , "  o  train0/enter/WD/C_SCH"
    , "  o  train0/enter/WD/F_SCH"
    , "  o  train0/enter/WD/GRD"
    , "  o  train0/leave/CO/co0/assertion/hyp6/goal (202,1)"
    , "  o  train0/leave/CO/co0/assertion/hyp6/hypotheses (202,1)"
    , "  o  train0/leave/CO/co0/assertion/hyp6/relation (202,1)"
    , "  o  train0/leave/CO/co0/assertion/hyp6/step (204,1)"
    , "  o  train0/leave/CO/co0/assertion/hyp6/step (206,1)"
    , "  o  train0/leave/CO/co0/assertion/hyp6/step (208,1)"
    , "  o  train0/leave/CO/co0/main goal/goal (176,1)"
    , "  o  train0/leave/CO/co0/main goal/hypotheses (176,1)"
    , "  o  train0/leave/CO/co0/main goal/relation (176,1)"
    , "  o  train0/leave/CO/co0/main goal/step (178,1)"
    , "  o  train0/leave/CO/co0/main goal/step (180,1)"
    , "  o  train0/leave/CO/co0/main goal/step (182,1)"
    , "  o  train0/leave/CO/co0/main goal/step (184,1)"
    , "  o  train0/leave/CO/co0/new assumption (168,1)"
    , "  o  train0/leave/CO/co1/goal (367,1)"
    , "  o  train0/leave/CO/co1/hypotheses (367,1)"
    , "  o  train0/leave/CO/co1/relation (367,1)"
    , "  o  train0/leave/CO/co1/step (369,1)"
    , "  o  train0/leave/CO/co1/step (372,1)"
    , "  o  train0/leave/CO/co1/step (377,1)"
    , "  o  train0/leave/CO/co1/step (380,1)"
    , "  o  train0/leave/CO/co1/step (383,1)"
    , "  o  train0/leave/CO/co1/step (385,1)"
    , "  o  train0/leave/CO/co1/step (387,1)"
    , "  o  train0/leave/CO/co1/step (390,1)"
    , "  o  train0/leave/FIS/in@prime"
    , "  o  train0/leave/FIS/loc@prime"
    , "  o  train0/leave/INV/inv1"
    , "  o  train0/leave/INV/inv2/goal (98,1)"
    , "  o  train0/leave/INV/inv2/hypotheses (98,1)"
    , "  o  train0/leave/INV/inv2/relation (98,1)"
    , "  o  train0/leave/INV/inv2/step (100,1)"
    , "  o  train0/leave/INV/inv2/step (102,1)"
    , "  o  train0/leave/INV/inv2/step (104,1)"
    , "  o  train0/leave/INV/inv2/step (106,1)"
    , " xxx train0/leave/SCH"
    , "  o  train0/leave/SCH/train0/1/REF/weaken"
    , "  o  train0/leave/WD/ACT/a0"
    , "  o  train0/leave/WD/ACT/a3"
    , "  o  train0/leave/WD/C_SCH"
    , "  o  train0/leave/WD/F_SCH"
    , "  o  train0/leave/WD/GRD"
    , "  o  train0/tr0/TR/WD"
    , "passed 108 / 109"
    ]

case1 :: IO (String, Map Label Sequent)
case1 = do
    r <- list_file_obligations path0
    case r of
        Right [m] -> do
            let h :: SomeException -> IO (String, Map Label Sequent)
                h x = return (show x, snd m)
            handle h $ do
                (s,_,_) <- str_verify_machine $ fst m
                return (s, snd m)
        x -> return (show x, empty)
        
result2 :: String
result2 = unlines (
        push
     ++ train_decl False False
     ++ set_decl_smt2 []
     ++ comp_facts [] ++ -- set_decl_smt2 ++
     [  "(assert (not (exists ( (in (set TRAIN)) )"
     ,  "                     (and true (= in empty-set@@TRAIN)))))" ]
     ++ named_facts ++
     [  "; asm2"
     ,  "(assert (and (not (= ent ext))"
     ,  "             (not (elem@@BLK ent PLF))"
     ,  "             (not (elem@@BLK ext PLF))))"
     ,  "; asm3"
     ,  "(assert (forall ( (p BLK) )"
     ,  "                (! (= (not (= p ext))"
     ,  "                      (elem@@BLK p (union (mk-set@@BLK ent) PLF)))"
     ,  "                   :pattern"
     ,  "                   ())))"
     ,  "; asm4"
     ,  "(assert (forall ( (p BLK) )"
     ,  "                (! (= (not (= p ent))"
     ,  "                      (elem@@BLK p (union (mk-set@@BLK ext) PLF)))"
     ,  "                   :pattern"
     ,  "                   ())))"
     ,  "; asm5"
     ,  "(assert (forall ( (p BLK) )"
     ,  "                (! (= (or (= p ent) (= p ext)) (not (elem@@BLK p PLF)))"
     ,  "                   :pattern"
     ,  "                   ())))"
     ,  "; axm0"
     ,  "(assert (= BLK"
     ,  "           (union (union (mk-set@@BLK ent) (mk-set@@BLK ext)) PLF)))"
     ,  "(assert (not (= empty-set@@TRAIN empty-set@@TRAIN)))"
     ] 
     ++ check_sat
     ++ pop )

pop :: [String]
pop = []

push :: [String]
push = []

case2 :: IO String
case2 = do
        pos <- list_file_obligations path0
        case pos of
            Right [(_,pos)] -> do
                let po = pos ! label "train0/INIT/FIS/in"
                let cmd = concatMap pretty_print' $ z3_code po
                return cmd
            x -> return $ show x

filterAssert :: (String -> Bool) -> [String] -> [String]
filterAssert p xs = concatMap lines $ L.filter p $ groupBrack xs

result20 :: String
result20 = 
    let f = filterAssert (not . (\x -> any (`L.isInfixOf` x) xs)) 
        xs = [ "dom-rest@@TRAIN@@BLK"
             , "dom-subt@@TRAIN@@BLK" 
             , "dom@@TRAIN@@BLK" 
             , "mk-set@@TRAIN"
             , "compl@@TRAIN"
             , "elem@@TRAIN"
             , "empty-set@@TRAIN"
             , "set-diff@@TRAIN" ]
    in
    unlines (
        push
     ++ train_decl False False
     ++ f (set_decl_smt2 [WithPFun])
     ++ f (comp_facts [WithPFun]) ++ 
     [  "(assert (not (exists ( (loc (pfun TRAIN BLK)) )"
     ,  "                     (and true (= loc empty-fun@@TRAIN@@BLK)))))" ]
     ++ named_facts ++
     [  "; asm2"
     ,  "(assert (and (not (= ent ext))"
     ,  "             (not (elem@@BLK ent PLF))"
     ,  "             (not (elem@@BLK ext PLF))))"
     ,  "; asm3"
     ,  "(assert (forall ( (p BLK) )"
     ,  "                (! (= (not (= p ext))"
     ,  "                      (elem@@BLK p (union (mk-set@@BLK ent) PLF)))"
     ,  "                   :pattern"
     ,  "                   ())))"
     ,  "; asm4"
     ,  "(assert (forall ( (p BLK) )"
     ,  "                (! (= (not (= p ent))"
     ,  "                      (elem@@BLK p (union (mk-set@@BLK ext) PLF)))"
     ,  "                   :pattern"
     ,  "                   ())))"
     ,  "; asm5"
     ,  "(assert (forall ( (p BLK) )"
     ,  "                (! (= (or (= p ent) (= p ext)) (not (elem@@BLK p PLF)))"
     ,  "                   :pattern"
     ,  "                   ())))"
     ,  "; axm0"
     ,  "(assert (= BLK"
     ,  "           (union (union (mk-set@@BLK ent) (mk-set@@BLK ext)) PLF)))"
     ,  "(assert (not (= empty-fun@@TRAIN@@BLK empty-fun@@TRAIN@@BLK)))"
     ] 
     ++ check_sat
     ++ pop )

case20 :: IO String
case20 = do
        pos <- list_file_obligations path0
        case pos of
            Right [(_,pos)] -> do
                let po = pos ! label "train0/INIT/FIS/loc"
                let cmd = concatMap pretty_print' $ z3_code po
                return cmd
            x -> return $ show x
            
result3 :: String
result3 = unlines (
     push ++
     train_decl False True ++ 
     set_decl_smt2 [WithPFun] ++ 
     comp_facts [WithPFun] ++
     [  "(assert (not (exists ( (in@prime (set TRAIN)) )"
     ,  "                     (and true"
     ,  "                          (= in@prime (set-diff@@TRAIN in (mk-set@@TRAIN t)))))))" ]
     ++ named_facts ++
     [  "; asm2"
     ,  "(assert (and (not (= ent ext))"
     ,  "             (not (elem@@BLK ent PLF))"
     ,  "             (not (elem@@BLK ext PLF))))"
     ,  "; asm3"
     ,  "(assert (forall ( (p BLK) )"
     ,  "                (! (= (not (= p ext))"
     ,  "                      (elem@@BLK p (union (mk-set@@BLK ent) PLF)))"
     ,  "                   :pattern"
     ,  "                   ())))"
     ,  "; asm4"
     ,  "(assert (forall ( (p BLK) )"
     ,  "                (! (= (not (= p ent))"
     ,  "                      (elem@@BLK p (union (mk-set@@BLK ext) PLF)))"
     ,  "                   :pattern"
     ,  "                   ())))"
     ,  "; asm5"
     ,  "(assert (forall ( (p BLK) )"
     ,  "                (! (= (or (= p ent) (= p ext)) (not (elem@@BLK p PLF)))"
     ,  "                   :pattern"
     ,  "                   ())))"
     ,  "; axm0"
     ,  "(assert (= BLK"
     ,  "           (union (union (mk-set@@BLK ent) (mk-set@@BLK ext)) PLF)))"
     ,  "; grd0"
     ,  "(assert (and (= (apply@@TRAIN@@BLK loc t) ext)"
     ,  "             (elem@@TRAIN t in)))"
     ,  "; inv1"
     ,  "(assert (forall ( (t TRAIN) )"
     ,  "                (! (=> (elem@@TRAIN t in)"
     ,  "                       (elem@@BLK (apply@@TRAIN@@BLK loc t) BLK))"
     ,  "                   :pattern"
     ,  "                   ( (elem@@BLK (apply@@TRAIN@@BLK loc t) BLK) ))))"
     ,  "; inv2"
     ,  "(assert (= (dom@@TRAIN@@BLK loc) in))"
     ,  "(assert (not (= (set-diff@@TRAIN in (mk-set@@TRAIN t))"
     ,  "                (set-diff@@TRAIN in (mk-set@@TRAIN t)))))"
     ] ++ 
     check_sat ++
     pop )

case3 :: IO String
case3 = do
        pos <- list_file_obligations path0
        case pos of
            Right [(_,pos)] -> do
                let po = pos ! label "train0/leave/FIS/in@prime"
                let cmd = concatMap pretty_print' $ z3_code po
                return cmd
            x -> return $ show x

result19 :: String
result19 = unlines (
     push ++ 
     train_decl False True ++ 
     set_decl_smt2 [WithPFun] ++ 
     comp_facts [WithPFun] ++
     [  "(assert (not (exists ( (loc@prime (pfun TRAIN BLK)) )"
     ,  "                     (and true"
     ,  "                          (= loc@prime"
     ,  "                             (dom-subt@@TRAIN@@BLK (mk-set@@TRAIN t) loc))))))" ]
     ++ named_facts ++
     [  "; asm2"
     ,  "(assert (and (not (= ent ext))"
     ,  "             (not (elem@@BLK ent PLF))"
     ,  "             (not (elem@@BLK ext PLF))))"
     ,  "; asm3"
     ,  "(assert (forall ( (p BLK) )"
     ,  "                (! (= (not (= p ext))"
     ,  "                      (elem@@BLK p (union (mk-set@@BLK ent) PLF)))"
     ,  "                   :pattern"
     ,  "                   ())))"
     ,  "; asm4"
     ,  "(assert (forall ( (p BLK) )"
     ,  "                (! (= (not (= p ent))"
     ,  "                      (elem@@BLK p (union (mk-set@@BLK ext) PLF)))"
     ,  "                   :pattern"
     ,  "                   ())))"
     ,  "; asm5"
     ,  "(assert (forall ( (p BLK) )"
     ,  "                (! (= (or (= p ent) (= p ext)) (not (elem@@BLK p PLF)))"
     ,  "                   :pattern"
     ,  "                   ())))"
     ,  "; axm0"
     ,  "(assert (= BLK"
     ,  "           (union (union (mk-set@@BLK ent) (mk-set@@BLK ext)) PLF)))"
     ,  "; grd0"
     ,  "(assert (and (= (apply@@TRAIN@@BLK loc t) ext)"
     ,  "             (elem@@TRAIN t in)))"
     ,  "; inv1"
     ,  "(assert (forall ( (t TRAIN) )"
     ,  "                (! (=> (elem@@TRAIN t in)"
     ,  "                       (elem@@BLK (apply@@TRAIN@@BLK loc t) BLK))"
     ,  "                   :pattern"
     ,  "                   ( (elem@@BLK (apply@@TRAIN@@BLK loc t) BLK) ))))"
     ,  "; inv2"
     ,  "(assert (= (dom@@TRAIN@@BLK loc) in))"
     ,  "(assert (not (= (dom-subt@@TRAIN@@BLK (mk-set@@TRAIN t) loc)"
     ,  "                (dom-subt@@TRAIN@@BLK (mk-set@@TRAIN t) loc))))"
     ] ++ 
     check_sat ++
     pop )

case19 :: IO String
case19 = do
        pos <- list_file_obligations path0
        case pos of
            Right [(_,pos)] -> do
                let po = pos ! label "train0/leave/FIS/loc@prime"
                let cmd = concatMap pretty_print' $ z3_code po
                return cmd
            x -> return $ show x

result4 :: String
result4 = unlines ( 
    push ++
    train_decl False True ++ 
    set_decl_smt2 [WithPFun] ++ 
    comp_facts [WithPFun] ++
    named_facts ++
    [ "; asm2"
    , "(assert (and (not (= ent ext))"
    , "             (not (elem@@BLK ent PLF))"
    , "             (not (elem@@BLK ext PLF))))"
    , "; asm3"
    , "(assert (forall ( (p BLK) )"
    , "                (! (= (not (= p ext))"
    , "                      (elem@@BLK p (union (mk-set@@BLK ent) PLF)))"
    , "                   :pattern"
    , "                   ())))"
    , "; asm4"
    , "(assert (forall ( (p BLK) )"
    , "                (! (= (not (= p ent))"
    , "                      (elem@@BLK p (union (mk-set@@BLK ext) PLF)))"
    , "                   :pattern"
    , "                   ())))"
    , "; asm5"
    , "(assert (forall ( (p BLK) )"
    , "                (! (= (or (= p ent) (= p ext)) (not (elem@@BLK p PLF)))"
    , "                   :pattern"
    , "                   ())))"
    , "; axm0"
    , "(assert (= BLK"
    , "           (union (union (mk-set@@BLK ent) (mk-set@@BLK ext)) PLF)))"
    , "; c0"
    , "(assert (elem@@TRAIN t in))"
    , "; inv1"
    , "(assert (forall ( (t TRAIN) )"
    , "                (! (=> (elem@@TRAIN t in)"
    , "                       (elem@@BLK (apply@@TRAIN@@BLK loc t) BLK))"
    , "                   :pattern"
    , "                   ( (elem@@BLK (apply@@TRAIN@@BLK loc t) BLK) ))))"
    , "; inv2"
    , "(assert (= (dom@@TRAIN@@BLK loc) in))"
    , "(assert (not (and (= (apply@@TRAIN@@BLK loc t) ext)"
    , "                  (elem@@TRAIN t in))))"
    ] ++ 
    check_sat ++
    pop )

case4 :: IO String
case4 = do
        pos <- list_file_obligations path0
        case pos of
            Right [(_,pos)] -> do
                let po = pos ! label "train0/leave/SCH"
                let cmd = concatMap pretty_print' $ z3_code po
                return cmd
            x -> return $ show x

result5 :: String
result5 = unlines ( 
    push ++
    train_decl True True ++ 
    set_decl_smt2 [WithPFun] ++ 
    comp_facts [WithPFun] ++
    [  "(assert (not (exists ( (t@param TRAIN) )"
    ,  "                     (and true"
    ,  "                          (and (=> (elem@@TRAIN t in) (elem@@TRAIN t@param in))"
    ,  "                               (=> (and (= in@prime"
    ,  "                                           (set-diff@@TRAIN in (mk-set@@TRAIN t@param)))"
    ,  "                                        (= loc@prime"
    ,  "                                           (dom-subt@@TRAIN@@BLK (mk-set@@TRAIN t@param) loc))"
    ,  "                                        (elem@@TRAIN t@param in)"
    ,  "                                        (= (apply@@TRAIN@@BLK loc t@param) ext)"
    ,  "                                        (elem@@TRAIN t@param in))"
    ,  "                                   (=> (elem@@TRAIN t in) (not (elem@@TRAIN t in@prime)))))))))" ]
    ++ named_facts ++
    [  "; asm2"
    ,  "(assert (and (not (= ent ext))"
    ,  "             (not (elem@@BLK ent PLF))"
    ,  "             (not (elem@@BLK ext PLF))))"
    ,  "; asm3"
    ,  "(assert (forall ( (p BLK) )"
    ,  "                (! (= (not (= p ext))"
    ,  "                      (elem@@BLK p (union (mk-set@@BLK ent) PLF)))"
    ,  "                   :pattern"
    ,  "                   ())))"
    ,  "; asm4"
    ,  "(assert (forall ( (p BLK) )"
    ,  "                (! (= (not (= p ent))"
    ,  "                      (elem@@BLK p (union (mk-set@@BLK ext) PLF)))"
    ,  "                   :pattern"
    ,  "                   ())))"
    ,  "; asm5"
    ,  "(assert (forall ( (p BLK) )"
    ,  "                (! (= (or (= p ent) (= p ext)) (not (elem@@BLK p PLF)))"
    ,  "                   :pattern"
    ,  "                   ())))"
    ,  "; axm0"
    ,  "(assert (= BLK"
    ,  "           (union (union (mk-set@@BLK ent) (mk-set@@BLK ext)) PLF)))"
    ,  "; inv1"
    ,  "(assert (forall ( (t TRAIN) )"
    ,  "                (! (=> (elem@@TRAIN t in)"
    ,  "                       (elem@@BLK (apply@@TRAIN@@BLK loc t) BLK))"
    ,  "                   :pattern"
    ,  "                   ( (elem@@BLK (apply@@TRAIN@@BLK loc t) BLK) ))))"
    ,  "; inv2"
    ,  "(assert (= (dom@@TRAIN@@BLK loc) in))"
    ,  "(assert (not (exists ( (t@param TRAIN) )"
    ,  "                     (and true"
    ,  "                          (and (=> (elem@@TRAIN t in) (elem@@TRAIN t@param in))"
    ,  "                               (=> (and (= in@prime"
    ,  "                                           (set-diff@@TRAIN in (mk-set@@TRAIN t@param)))"
    ,  "                                        (= loc@prime"
    ,  "                                           (dom-subt@@TRAIN@@BLK (mk-set@@TRAIN t@param) loc))"
    ,  "                                        (elem@@TRAIN t@param in)"
    ,  "                                        (= (apply@@TRAIN@@BLK loc t@param) ext)"
    ,  "                                        (elem@@TRAIN t@param in))"
    ,  "                                   (=> (elem@@TRAIN t in) (not (elem@@TRAIN t in@prime)))))))))"
    ] ++ 
    check_sat ++
    pop  )

case5 :: IO String
case5 = do
        pos <- list_file_obligations path0
        case pos of
            Right [(_,pos)] -> do
                let po  = pos ! label "train0/TR/tr0/t@param"
                let cmd = concatMap pretty_print' $ z3_code po
                return cmd
            x -> return $ show x

--result6 = unlines ( 
--        train_decl True ++ 
--        set_decl_smt2 ++ 
--        comp_facts ++
--        [  "(assert (= BLK (bunion@@BLK (bunion@@BLK (mk-set@@BLK ent) (mk-set@@BLK ext)) PLF)))"
--        ,  "(assert (elem@@TRAIN t in))"
--        ,  "(assert (= (dom@@TRAIN@@BLK loc) in))"
--        ,  "(assert (elem@@TRAIN t in))"
--        ,  "(assert (= in@prime (set-diff@@TRAIN in (mk-set@@TRAIN t))))"
--        ,  "(assert (= loc@prime (dom-subt@@TRAIN@@BLK (mk-set@@TRAIN t) loc)))"
--        ,  "(assert (not (not (elem@@TRAIN t in@prime))))"
--        ,  "(check-sat-using (or-else (then qe smt) (then skip smt) (then (using-params simplify :expand-power true) smt)))"
--        ] )
----    where
----        in_prime = ["(declare-const in@prime (set TRAIN))"]
----        loc_prime = ["(declare-const loc@prime (pfun TRAIN BLK))"]
--
--
--case6 = do
--        pos <- list_file_obligations path0
--        case pos of
--            Right [(_,pos)] -> do
--                let po = pos ! label "m0/leave/TR/NEG/tr0"
--                let cmd = unlines $ map (show . as_tree) $ z3_code po
--                return cmd
--            x -> return $ show x

result12 :: String
result12 = unlines ( 
    push ++
    train_decl True True ++ 
    set_decl_smt2 [WithPFun] ++ 
    comp_facts [WithPFun] ++
    named_facts ++
    [  "; a0"
    ,  "(assert (= in@prime (set-diff@@TRAIN in (mk-set@@TRAIN t))))"
    ,  "; a3"
    ,  "(assert (= loc@prime"
    ,  "           (dom-subt@@TRAIN@@BLK (mk-set@@TRAIN t) loc)))"
    ,  "; asm2"
    ,  "(assert (and (not (= ent ext))"
    ,  "             (not (elem@@BLK ent PLF))"
    ,  "             (not (elem@@BLK ext PLF))))"
    ,  "; asm3"
    ,  "(assert (forall ( (p BLK) )"
    ,  "                (! (= (not (= p ext))"
    ,  "                      (elem@@BLK p (union (mk-set@@BLK ent) PLF)))"
    ,  "                   :pattern"
    ,  "                   ())))"
    ,  "; asm4"
    ,  "(assert (forall ( (p BLK) )"
    ,  "                (! (= (not (= p ent))"
    ,  "                      (elem@@BLK p (union (mk-set@@BLK ext) PLF)))"
    ,  "                   :pattern"
    ,  "                   ())))"
    ,  "; asm5"
    ,  "(assert (forall ( (p BLK) )"
    ,  "                (! (= (or (= p ent) (= p ext)) (not (elem@@BLK p PLF)))"
    ,  "                   :pattern"
    ,  "                   ())))"
    ,  "; axm0"
    ,  "(assert (= BLK"
    ,  "           (union (union (mk-set@@BLK ent) (mk-set@@BLK ext)) PLF)))"
    ,  "; grd0"
    ,  "(assert (and (= (apply@@TRAIN@@BLK loc t) ext)"
    ,  "             (elem@@TRAIN t in)))"
    ,  "; inv1"
    ,  "(assert (forall ( (t TRAIN) )"
    ,  "                (! (=> (elem@@TRAIN t in)"
    ,  "                       (elem@@BLK (apply@@TRAIN@@BLK loc t) BLK))"
    ,  "                   :pattern"
    ,  "                   ( (elem@@BLK (apply@@TRAIN@@BLK loc t) BLK) ))))"
    ,  "; inv2"
    ,  "(assert (= (dom@@TRAIN@@BLK loc) in))"
    ,  "(assert (not (= (dom@@TRAIN@@BLK loc@prime) in@prime)))"
    ] ++ 
    check_sat ++
    pop )

case12 :: IO String
case12 = do
        r <- parse_machine path0
        case r of
            Right [m] -> do
                let po = raw_machine_pos m ! label "train0/leave/INV/inv2"
                let cmd = concatMap pretty_print' $ z3_code po
                return cmd
            x -> return $ show x

    --------------------
    -- Error handling --
    --------------------
result7 :: Either [Error] a
result7 = Left [Error "unrecognized term: t" (LI path7 54 3)]

path7 :: String
path7 = "Tests/train-station-err0.tex"

case7 :: IO (Either [Error] [Machine])
case7 = parse_machine path7

result8 :: Either [Error] a
result8 = Left [Error "event 'leave' is undeclared" (LI path8 42 15)]

path8 :: String
path8 = "Tests/train-station-err1.tex"

case8 :: IO (Either [Error] [Machine])
case8 = parse_machine path8

result9 :: Either [Error] a
result9 = Left [Error "event 'leave' is undeclared" (LI path9 51 15)]

path9 :: String
path9 = "Tests/train-station-err2.tex"

case9 :: IO (Either [Error] [Machine])
case9 = parse_machine path9

result10 :: Either [Error] a
result10 = Left [Error "event 'leave' is undeclared" (LI path10 55 15)]

path10 :: String
path10 = "Tests/train-station-err3.tex"

case10 :: IO (Either [Error] [Machine])
case10 = parse_machine path10

result11 :: Either [Error] a
result11 = Left [Error "event 'leave' is undeclared" (LI path11 59 15)]

path11 :: String
path11 = "Tests/train-station-err4.tex"

case11 :: IO (Either [Error] [Machine])
case11 = parse_machine path11

path13 :: String
path13 = "Tests/train-station-err5.tex"

result13 :: String
result13 = unlines
    [ "  o  train0/INIT/FIS/in"
    , "  o  train0/INIT/FIS/loc"
    , "  o  train0/INIT/INV/inv1"
    , "  o  train0/INIT/INV/inv2"
    , "  o  train0/INIT/WD"
    , "  o  train0/INV/WD"
    , "  o  train0/SKIP/CO/co0"
    , "  o  train0/SKIP/CO/co1"
    , "  o  train0/TR/tr0/t@param"
    , "  o  train0/co0/CO/WD"
    , "  o  train0/co1/CO/WD"
    , "  o  train0/enter/CO/co0/goal (220,1)"
    , "  o  train0/enter/CO/co0/hypotheses (220,1)"
    , "  o  train0/enter/CO/co0/relation (220,1)"
    , "  o  train0/enter/CO/co0/step (227,1)"
    , "  o  train0/enter/CO/co0/step (229,1)"
    , "  o  train0/enter/CO/co0/step (232,1)"
    , "  o  train0/enter/CO/co0/step (235,1)"
    , "  o  train0/enter/CO/co0/step (238,1)"
    , "  o  train0/enter/CO/co0/step (240,1)"
    , "  o  train0/enter/CO/co0/step (242,1)"
    , "  o  train0/enter/CO/co0/step (244,1)"
    , "  o  train0/enter/CO/co1"
    , "  o  train0/enter/FIS/in@prime"
    , "  o  train0/enter/FIS/loc@prime"
    , "  o  train0/enter/INV/inv1"
    , "  o  train0/enter/INV/inv2/goal (77,1)"
    , "  o  train0/enter/INV/inv2/hypotheses (77,1)"
    , "  o  train0/enter/INV/inv2/relation (77,1)"
    , "  o  train0/enter/INV/inv2/step (79,1)"
    , "  o  train0/enter/INV/inv2/step (81,1)"
    , "  o  train0/enter/INV/inv2/step (83,1)"
    , "  o  train0/enter/INV/inv2/step (85,1)"
    , "  o  train0/enter/INV/inv2/step (87,1)"
    , "  o  train0/enter/SAF/s0"
    , "  o  train0/enter/SAF/s1"
    , "  o  train0/enter/SCH"
    , "  o  train0/enter/WD/ACT/a1"
    , "  o  train0/enter/WD/ACT/a2"
    , "  o  train0/enter/WD/C_SCH"
    , "  o  train0/enter/WD/F_SCH"
    , "  o  train0/enter/WD/GRD"
    , " xxx train0/leave/CO/co0/goal (173,1)"
    , "  o  train0/leave/CO/co0/hypotheses (173,1)"
    , "  o  train0/leave/CO/co0/relation (173,1)"
    , " xxx train0/leave/CO/co0/step (175,1)"
    , "  o  train0/leave/CO/co0/step (177,1)"
    , "  o  train0/leave/CO/co0/step (179,1)"
    , " xxx train0/leave/CO/co0/step (181,1)"
    , "  o  train0/leave/CO/co0/step (183,1)"
    , "  o  train0/leave/CO/co0/step (185,1)"
    , " xxx train0/leave/CO/co1/goal (250,1)"
    , "  o  train0/leave/CO/co1/hypotheses (250,1)"
    , "  o  train0/leave/CO/co1/relation (250,1)"
    , "  o  train0/leave/CO/co1/step (252,1)"
    , "  o  train0/leave/CO/co1/step (255,1)"
    , "  o  train0/leave/CO/co1/step (260,1)"
    , "  o  train0/leave/CO/co1/step (263,1)"
    , "  o  train0/leave/CO/co1/step (266,1)"
    , "  o  train0/leave/CO/co1/step (268,1)"
    , "  o  train0/leave/CO/co1/step (270,1)"
    , "  o  train0/leave/CO/co1/step (273,1)"
    , "  o  train0/leave/FIS/in@prime"
    , "  o  train0/leave/FIS/loc@prime"
    , "  o  train0/leave/INV/inv1"
    , "  o  train0/leave/INV/inv2/goal (98,1)"
    , "  o  train0/leave/INV/inv2/hypotheses (98,1)"
    , "  o  train0/leave/INV/inv2/relation (98,1)"
    , "  o  train0/leave/INV/inv2/step (100,1)"
    , "  o  train0/leave/INV/inv2/step (102,1)"
    , "  o  train0/leave/INV/inv2/step (104,1)"
    , "  o  train0/leave/INV/inv2/step (106,1)"
    , "  o  train0/leave/SAF/s0"
    , "  o  train0/leave/SAF/s1"
    , " xxx train0/leave/SCH"
    , "  o  train0/leave/SCH/train0/1/REF/weaken"
    , "  o  train0/leave/WD/ACT/a0"
    , "  o  train0/leave/WD/ACT/a3"
    , "  o  train0/leave/WD/C_SCH"
    , "  o  train0/leave/WD/F_SCH"
    , "  o  train0/leave/WD/GRD"
    , "  o  train0/s0/SAF/WD/lhs"
    , "  o  train0/s0/SAF/WD/rhs"
    , "  o  train0/s1/SAF/WD/lhs"
    , "  o  train0/s1/SAF/WD/rhs"
    , "  o  train0/tr0/TR/WD"
    , "passed 81 / 86"
    ]

case13 :: IO (String, Map Label Sequent)
case13 = verify path13

verify :: FilePath -> IO (String, Map Label Sequent)
verify path = do
    r <- list_file_obligations path
    case r of
        Right [(m,pos)] -> do
            (s,_,_) <- str_verify_machine m
            return (s, pos)
        x -> return (show x, empty)

path14 :: String
path14 = "Tests/train-station-err6.tex"

result14 :: String
result14 = unlines
    [ "  o  train0/INIT/FIS/in"
    , "  o  train0/INIT/FIS/loc"
    , "  o  train0/INIT/INV/inv1"
    , "  o  train0/INIT/INV/inv2"
    , "  o  train0/INIT/WD"
    , "  o  train0/INV/WD"
    , "  o  train0/SKIP/CO/co0"
    , "  o  train0/SKIP/CO/co1"
    , "  o  train0/TR/tr0/t@param"
    , "  o  train0/co0/CO/WD"
    , "  o  train0/co1/CO/WD"
    , "  o  train0/enter/CO/co0/case 1/goal (222,1)"
    , "  o  train0/enter/CO/co0/case 1/hypotheses (222,1)"
    , "  o  train0/enter/CO/co0/case 1/relation (222,1)"
    , "  o  train0/enter/CO/co0/case 1/step (224,1)"
    , "  o  train0/enter/CO/co0/case 1/step (226,1)"
    , " xxx train0/enter/CO/co0/completeness (220,1)"
    , "  o  train0/enter/CO/co1"
    , "  o  train0/enter/FIS/in@prime"
    , "  o  train0/enter/FIS/loc@prime"
    , "  o  train0/enter/INV/inv1"
    , "  o  train0/enter/INV/inv2/goal (77,1)"
    , "  o  train0/enter/INV/inv2/hypotheses (77,1)"
    , "  o  train0/enter/INV/inv2/relation (77,1)"
    , "  o  train0/enter/INV/inv2/step (79,1)"
    , "  o  train0/enter/INV/inv2/step (81,1)"
    , "  o  train0/enter/INV/inv2/step (83,1)"
    , "  o  train0/enter/INV/inv2/step (85,1)"
    , "  o  train0/enter/INV/inv2/step (87,1)"
    , "  o  train0/enter/SAF/s0"
    , "  o  train0/enter/SAF/s1"
    , "  o  train0/enter/SCH"
    , "  o  train0/enter/WD/ACT/a1"
    , "  o  train0/enter/WD/ACT/a2"
    , "  o  train0/enter/WD/C_SCH"
    , "  o  train0/enter/WD/F_SCH"
    , "  o  train0/enter/WD/GRD"
    , "  o  train0/leave/CO/co0/goal (172,1)"
    , "  o  train0/leave/CO/co0/hypotheses (172,1)"
    , "  o  train0/leave/CO/co0/relation (172,1)"
    , "  o  train0/leave/CO/co0/step (174,1)"
    , "  o  train0/leave/CO/co0/step (176,1)"
    , "  o  train0/leave/CO/co0/step (180,1)"
    , "  o  train0/leave/CO/co0/step (182,1)"
    , "  o  train0/leave/CO/co1/goal (255,1)"
    , "  o  train0/leave/CO/co1/hypotheses (255,1)"
    , "  o  train0/leave/CO/co1/relation (255,1)"
    , "  o  train0/leave/CO/co1/step (257,1)"
    , "  o  train0/leave/CO/co1/step (260,1)"
    , "  o  train0/leave/CO/co1/step (265,1)"
    , "  o  train0/leave/CO/co1/step (268,1)"
    , "  o  train0/leave/CO/co1/step (271,1)"
    , "  o  train0/leave/CO/co1/step (273,1)"
    , "  o  train0/leave/CO/co1/step (275,1)"
    , "  o  train0/leave/CO/co1/step (278,1)"
    , "  o  train0/leave/FIS/in@prime"
    , "  o  train0/leave/FIS/loc@prime"
    , "  o  train0/leave/INV/inv1"
    , "  o  train0/leave/INV/inv2/goal (98,1)"
    , "  o  train0/leave/INV/inv2/hypotheses (98,1)"
    , "  o  train0/leave/INV/inv2/relation (98,1)"
    , "  o  train0/leave/INV/inv2/step (100,1)"
    , "  o  train0/leave/INV/inv2/step (102,1)"
    , "  o  train0/leave/INV/inv2/step (104,1)"
    , "  o  train0/leave/INV/inv2/step (106,1)"
    , "  o  train0/leave/SAF/s0"
    , "  o  train0/leave/SAF/s1"
    , " xxx train0/leave/SCH"
    , "  o  train0/leave/SCH/train0/1/REF/weaken"
    , "  o  train0/leave/WD/ACT/a0"
    , "  o  train0/leave/WD/ACT/a3"
    , "  o  train0/leave/WD/C_SCH"
    , "  o  train0/leave/WD/F_SCH"
    , "  o  train0/leave/WD/GRD"
    , "  o  train0/s0/SAF/WD/lhs"
    , "  o  train0/s0/SAF/WD/rhs"
    , "  o  train0/s1/SAF/WD/lhs"
    , "  o  train0/s1/SAF/WD/rhs"
    , "  o  train0/tr0/TR/WD"
    , "passed 77 / 79"
    ]
        
case14 :: IO (String, Map Label Sequent)
case14 = verify path14
    
path15 :: String
path15 = "Tests/train-station-err7.tex"

result15 :: String
result15 = unlines
    [ "  o  train0/INIT/FIS/in"
    , "  o  train0/INIT/FIS/loc"
    , "  o  train0/INIT/INV/inv1"
    , "  o  train0/INIT/INV/inv2"
    , "  o  train0/INIT/WD"
    , "  o  train0/INV/WD"
    , "  o  train0/SKIP/CO/co0"
    , "  o  train0/SKIP/CO/co1"
    , "  o  train0/TR/tr0/t@param"
    , "  o  train0/co0/CO/WD"
    , "  o  train0/co1/CO/WD"
    , "  o  train0/enter/CO/co0/case 1/goal (234,1)"
    , "  o  train0/enter/CO/co0/case 1/hypotheses (234,1)"
    , "  o  train0/enter/CO/co0/case 1/relation (234,1)"
    , "  o  train0/enter/CO/co0/case 1/step (236,1)"
    , "  o  train0/enter/CO/co0/case 1/step (238,1)"
    , "  o  train0/enter/CO/co0/case 2/goal (246,1)"
    , "  o  train0/enter/CO/co0/case 2/hypotheses (246,1)"
    , "  o  train0/enter/CO/co0/case 2/relation (246,1)"
    , "  o  train0/enter/CO/co0/case 2/step (248,1)"
    , "  o  train0/enter/CO/co0/case 2/step (250,1)"
    , "  o  train0/enter/CO/co0/case 2/step (252,1)"
    , "  o  train0/enter/CO/co0/case 2/step (254,1)"
    , "  o  train0/enter/CO/co0/completeness (231,1)"
    , "  o  train0/enter/CO/co1"
    , "  o  train0/enter/FIS/in@prime"
    , "  o  train0/enter/FIS/loc@prime"
    , "  o  train0/enter/INV/inv1"
    , "  o  train0/enter/INV/inv2/goal (77,1)"
    , "  o  train0/enter/INV/inv2/hypotheses (77,1)"
    , "  o  train0/enter/INV/inv2/relation (77,1)"
    , "  o  train0/enter/INV/inv2/step (79,1)"
    , "  o  train0/enter/INV/inv2/step (81,1)"
    , "  o  train0/enter/INV/inv2/step (83,1)"
    , "  o  train0/enter/INV/inv2/step (85,1)"
    , "  o  train0/enter/INV/inv2/step (87,1)"
    , "  o  train0/enter/SAF/s0"
    , "  o  train0/enter/SAF/s1"
    , "  o  train0/enter/SCH"
    , "  o  train0/enter/WD/ACT/a1"
    , "  o  train0/enter/WD/ACT/a2"
    , "  o  train0/enter/WD/C_SCH"
    , "  o  train0/enter/WD/F_SCH"
    , "  o  train0/enter/WD/GRD"
    , "  o  train0/leave/CO/co0/goal (180,1)"
    , "  o  train0/leave/CO/co0/hypotheses (180,1)"
    , " xxx train0/leave/CO/co0/new assumption (172,1)"
    , "  o  train0/leave/CO/co0/relation (180,1)"
    , "  o  train0/leave/CO/co0/step (182,1)"
    , " xxx train0/leave/CO/co0/step (184,1)"
    , "  o  train0/leave/CO/co1/goal (266,1)"
    , "  o  train0/leave/CO/co1/hypotheses (266,1)"
    , "  o  train0/leave/CO/co1/relation (266,1)"
    , "  o  train0/leave/CO/co1/step (268,1)"
    , "  o  train0/leave/CO/co1/step (271,1)"
    , "  o  train0/leave/CO/co1/step (276,1)"
    , "  o  train0/leave/CO/co1/step (279,1)"
    , "  o  train0/leave/CO/co1/step (282,1)"
    , "  o  train0/leave/CO/co1/step (284,1)"
    , "  o  train0/leave/CO/co1/step (286,1)"
    , "  o  train0/leave/CO/co1/step (289,1)"
    , "  o  train0/leave/FIS/in@prime"
    , "  o  train0/leave/FIS/loc@prime"
    , "  o  train0/leave/INV/inv1"
    , "  o  train0/leave/INV/inv2/goal (98,1)"
    , "  o  train0/leave/INV/inv2/hypotheses (98,1)"
    , "  o  train0/leave/INV/inv2/relation (98,1)"
    , "  o  train0/leave/INV/inv2/step (100,1)"
    , "  o  train0/leave/INV/inv2/step (102,1)"
    , "  o  train0/leave/INV/inv2/step (104,1)"
    , "  o  train0/leave/INV/inv2/step (106,1)"
    , "  o  train0/leave/SAF/s0"
    , "  o  train0/leave/SAF/s1"
    , " xxx train0/leave/SCH"
    , "  o  train0/leave/SCH/train0/1/REF/weaken"
    , "  o  train0/leave/WD/ACT/a0"
    , "  o  train0/leave/WD/ACT/a3"
    , "  o  train0/leave/WD/C_SCH"
    , "  o  train0/leave/WD/F_SCH"
    , "  o  train0/leave/WD/GRD"
    , "  o  train0/s0/SAF/WD/lhs"
    , "  o  train0/s0/SAF/WD/rhs"
    , "  o  train0/s1/SAF/WD/lhs"
    , "  o  train0/s1/SAF/WD/rhs"
    , "  o  train0/tr0/TR/WD"
    , "passed 82 / 85"
    ]
      
case15 :: IO (String, Map Label Sequent)
case15 = verify path15

path16 :: String
path16 = "Tests/train-station-t2.tex"

result16 :: String
result16 = unlines 
    [ "  o  train0/INIT/FIS/in"
    , "  o  train0/INIT/FIS/loc"
    , "  o  train0/INIT/INV/inv1"
    , "  o  train0/INIT/INV/inv2"
    , "  o  train0/INIT/WD"
    , "  o  train0/INV/WD"
    , "  o  train0/SKIP/CO/co0"
    , "  o  train0/SKIP/CO/co1"
    , "  o  train0/TR/tr0/t@param"
    , "  o  train0/co0/CO/WD"
    , "  o  train0/co1/CO/WD"
    , "  o  train0/enter/CO/co0/case 1/goal (292,1)"
    , "  o  train0/enter/CO/co0/case 1/hypotheses (292,1)"
    , "  o  train0/enter/CO/co0/case 1/relation (292,1)"
    , "  o  train0/enter/CO/co0/case 1/step (294,1)"
    , "  o  train0/enter/CO/co0/case 1/step (296,1)"
    , "  o  train0/enter/CO/co0/case 2/goal (304,1)"
    , "  o  train0/enter/CO/co0/case 2/hypotheses (304,1)"
    , "  o  train0/enter/CO/co0/case 2/relation (304,1)"
    , "  o  train0/enter/CO/co0/case 2/step (306,1)"
    , "  o  train0/enter/CO/co0/case 2/step (308,1)"
    , "  o  train0/enter/CO/co0/case 2/step (310,1)"
    , "  o  train0/enter/CO/co0/case 2/step (312,1)"
    , "  o  train0/enter/CO/co0/completeness (289,1)"
    , "  o  train0/enter/CO/co1/completeness (215,1)"
    , "  o  train0/enter/CO/co1/new assumption (202,1)"
    , "  o  train0/enter/CO/co1/part 1/goal (219,2)"
    , "  o  train0/enter/CO/co1/part 1/hypotheses (219,2)"
    , "  o  train0/enter/CO/co1/part 1/relation (219,2)"
    , "  o  train0/enter/CO/co1/part 1/step (221,2)"
    , "  o  train0/enter/CO/co1/part 1/step (223,2)"
    , "  o  train0/enter/CO/co1/part 2/case 1/goal (233,2)"
    , "  o  train0/enter/CO/co1/part 2/case 1/hypotheses (233,2)"
    , "  o  train0/enter/CO/co1/part 2/case 1/relation (233,2)"
    , "  o  train0/enter/CO/co1/part 2/case 1/step (235,2)"
    , "  o  train0/enter/CO/co1/part 2/case 1/step (237,2)"
    , "  o  train0/enter/CO/co1/part 2/case 2/goal (244,2)"
    , "  o  train0/enter/CO/co1/part 2/case 2/hypotheses (244,2)"
    , "  o  train0/enter/CO/co1/part 2/case 2/relation (244,2)"
    , "  o  train0/enter/CO/co1/part 2/case 2/step (246,2)"
    , "  o  train0/enter/CO/co1/part 2/case 2/step (248,2)"
    , "  o  train0/enter/CO/co1/part 2/case 2/step (250,2)"
    , "  o  train0/enter/CO/co1/part 2/completeness (230,2)"
    , "  o  train0/enter/FIS/in@prime"
    , "  o  train0/enter/FIS/loc@prime"
    , "  o  train0/enter/INV/inv1"
    , "  o  train0/enter/INV/inv2/goal (77,1)"
    , "  o  train0/enter/INV/inv2/hypotheses (77,1)"
    , "  o  train0/enter/INV/inv2/relation (77,1)"
    , "  o  train0/enter/INV/inv2/step (79,1)"
    , "  o  train0/enter/INV/inv2/step (81,1)"
    , "  o  train0/enter/INV/inv2/step (83,1)"
    , "  o  train0/enter/INV/inv2/step (85,1)"
    , "  o  train0/enter/INV/inv2/step (87,1)"
    , "  o  train0/enter/SAF/s0"
    , "  o  train0/enter/SAF/s1"
    , "  o  train0/enter/SCH"
    , "  o  train0/enter/WD/ACT/a1"
    , "  o  train0/enter/WD/ACT/a2"
    , "  o  train0/enter/WD/C_SCH"
    , "  o  train0/enter/WD/F_SCH"
    , "  o  train0/enter/WD/GRD"
    , "  o  train0/leave/CO/co0/goal (175,1)"
    , "  o  train0/leave/CO/co0/hypotheses (175,1)"
    , "  o  train0/leave/CO/co0/relation (175,1)"
    , "  o  train0/leave/CO/co0/step (182,1)"
    , "  o  train0/leave/CO/co0/step (184,1)"
    , "  o  train0/leave/CO/co0/step (186,1)"
    , "  o  train0/leave/CO/co0/step (188,1)"
    , "  o  train0/leave/CO/co1/goal (324,1)"
    , "  o  train0/leave/CO/co1/hypotheses (324,1)"
    , "  o  train0/leave/CO/co1/relation (324,1)"
    , "  o  train0/leave/CO/co1/step (326,1)"
    , "  o  train0/leave/CO/co1/step (329,1)"
    , "  o  train0/leave/CO/co1/step (334,1)"
    , "  o  train0/leave/CO/co1/step (337,1)"
    , "  o  train0/leave/CO/co1/step (340,1)"
    , "  o  train0/leave/CO/co1/step (342,1)"
    , "  o  train0/leave/CO/co1/step (344,1)"
    , "  o  train0/leave/CO/co1/step (347,1)"
    , "  o  train0/leave/FIS/in@prime"
    , "  o  train0/leave/FIS/loc@prime"
    , "  o  train0/leave/INV/inv1"
    , "  o  train0/leave/INV/inv2/goal (98,1)"
    , "  o  train0/leave/INV/inv2/hypotheses (98,1)"
    , "  o  train0/leave/INV/inv2/relation (98,1)"
    , "  o  train0/leave/INV/inv2/step (100,1)"
    , "  o  train0/leave/INV/inv2/step (102,1)"
    , "  o  train0/leave/INV/inv2/step (104,1)"
    , "  o  train0/leave/INV/inv2/step (106,1)"
    , "  o  train0/leave/SAF/s0"
    , "  o  train0/leave/SAF/s1"
    , " xxx train0/leave/SCH"
    , "  o  train0/leave/SCH/train0/1/REF/weaken"
    , "  o  train0/leave/WD/ACT/a0"
    , "  o  train0/leave/WD/ACT/a3"
    , "  o  train0/leave/WD/C_SCH"
    , "  o  train0/leave/WD/F_SCH"
    , "  o  train0/leave/WD/GRD"
    , "  o  train0/s0/SAF/WD/lhs"
    , "  o  train0/s0/SAF/WD/rhs"
    , "  o  train0/s1/SAF/WD/lhs"
    , "  o  train0/s1/SAF/WD/rhs"
    , "  o  train0/tr0/TR/WD"
    , "passed 103 / 104"
    ]

case16 :: IO (String, Map Label Sequent)
case16 = verify path16

path17 :: String
path17 = "Tests/train-station-err8.tex"

result17 :: String
result17 = unlines 
        [  "error (75,3): type of empty-fun@@TRAIN@@a is ill-defined: pfun [TRAIN,_a]"
        ,  "error (75,3): type of empty-fun@@TRAIN@@b is ill-defined: pfun [TRAIN,_b]"
        ,  "error (77,2): type of empty-fun@@TRAIN@@a is ill-defined: pfun [TRAIN,_a]"
        ]

case17 :: IO String
case17 = do
        r <- parse_machine path17
        case r of
            Right _ -> do
                return "successful verification"
            Left xs -> return $ unlines $ map format_error xs
        
path18 :: String
path18 = "Tests/train-station-err9.tex"

result18 :: String
result18 = unlines 
        [  "error (68,2): expression has type incompatible with its expected type:"
        ,  "  expression: (dom@@TRAIN@@BLK loc)"
        ,  "  actual type: set [TRAIN]"
        ,  "  expected type: Bool "
        ,  ""
        ,  "error (73,3): expression has type incompatible with its expected type:"
        ,  "  expression: (union in (mk-set@@TRAIN t))"
        ,  "  actual type: set [TRAIN]"
        ,  "  expected type: Bool "
        ,  ""
        ,  "error (118,3): expression has type incompatible with its expected type:"
        ,  "  expression: t"
        ,  "  actual type: TRAIN"
        ,  "  expected type: Bool "
        ,  ""
        ,  "error (123,2): expression has type incompatible with its expected type:"
        ,  "  expression: empty-set@@a"
        ,  "  actual type: set [_a]"
        ,  "  expected type: Bool "
        ,  ""
        ]

case18 :: IO String
case18 = do
        r <- parse_machine path18
        case r of
            Right _ -> do
                return "successful verification"
            Left xs -> return $ unlines $ map format_error xs

--get_proof_obl name = do
--        pos <- list_file_obligations path0
--        case pos of
--            Right [(_,pos)] -> do
--                let po = pos ! label name
--                let cmd = unlines $ map (show . as_tree) $ z3_code po
--                putStrLn cmd
--            x -> putStrLn $ show x

--list_proof_obl = do
--        pos <- list_file_obligations path0
--        case pos of
--            Right [(_,pos)] -> do   
--                forM_ (map show $ keys $ pos) putStrLn
--            _ -> return () -- $ show x
