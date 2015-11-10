{-# LANGUAGE OverloadedStrings, QuasiQuotes #-}
module Document.Tests.SmallMachine where

    -- Modules
import Document.Tests.Suite
import Document.Proof

import Logic.Expr
import Logic.Expr.QuasiQuote
import Logic.Proof

import UnitB.AST

    -- Libraries
import Control.Lens hiding ((.=))

import           Data.Map as M hiding ( map )
import qualified Data.List.NonEmpty as NE

import Tests.UnitTest

import Utilities.Syntactic

test_case :: TestCase
test_case = test

test :: TestCase
test = test_cases "small machine example" [
        (Case "test 0" 
            case0 $ 
            Right $ [m0_machine]),
        (Case "test 1 (separate machine blocks)" 
            case1 $ 
            Right $ [m1_machine]),
        (POCase "test 2 (verification, one failure)" 
            case2 result2),
        (POCase "test 3 (verification)" 
            case3 result3),
        (StringCase "test 4 (proof obligation, invariance)" 
            case4 result4),
        (StringCase "test 5 (co, 'skip' proof obligation)" 
            case5 result5),
        (POCase "test 6 (verification, coarse schedule stronger than guard)" 
            case6 result6),
        (StringCase "test 7 (schedulability proof obligation)" 
            case7 result7),
        (StringCase "test 8 (schedulability without selecting schedules (trivially true))" 
            case8 result8),
            -- default: false is no longer weakened away
        --(StringCase "test 9 (coarse schedule weakening, PO)" 
        --    case9 result9),
        (StringCase "test 10 (transient PO, enablement)" 
            case10 result10), 
        (StringCase "test 11 (transient PO, negation)" 
            case11 result11),
        (StringCase "test 12 name clash between coarse schedule and co properties" 
            case12 result12) ]

path0 :: String
path0 = "Tests/small_machine_t0.tex"

case0 :: IO (Either [Error] [Machine])
case0 = do
    parse path0
    
path1 :: String
path1 = "Tests/small_machine_t1.tex"

case1 :: IO (Either [Error] [Machine])
case1 = do
    parse path1

result2 :: String
result2 = unlines 
    [ "  o  m0/INIT/FIS/x"
    , "  o  m0/INIT/FIS/y"
    , "  o  m0/INIT/INV/inv0"
    , "  o  m0/INIT/INV/inv1"
    , "  o  m0/INIT/WD"
    , "  o  m0/INIT/WWD"
    , "  o  m0/INV/WD"
    , " xxx m0/TR/tr0/inc/EN"
    , "  o  m0/TR/tr0/inc/NEG"
    , "  o  m0/TR/tr0/leadsto/lhs"
    , "  o  m0/TR/tr0/leadsto/rhs"
    , "  o  m0/inc/FIS/x@prime"
    , "  o  m0/inc/FIS/y@prime"
    , "  o  m0/inc/INV/inv0"
    , " xxx m0/inc/INV/inv1"
    , "  o  m0/inc/WD/ACT/a0"
    , "  o  m0/inc/WD/ACT/a1"
    , "  o  m0/inc/WD/C_SCH"
    , "  o  m0/inc/WD/F_SCH"
    , "  o  m0/inc/WD/GRD"
    , "  o  m0/inc/WWD"
    , "  o  m0/prog0/PROG/WD/lhs"
    , "  o  m0/prog0/PROG/WD/rhs"
    , " xxx m0/prog0/REF/add"
    , "  o  m0/tr0/TR/WD"
    , "passed 22 / 25"
    ]

path2 :: String
path2 = "Tests/small_machine_t2.tex"

case2 :: IO (String, Map Label Sequent)
case2 =  verify path2 0

result3 :: String
result3 = unlines 
    [ "  o  m0/INIT/FIS/x"
    , "  o  m0/INIT/FIS/y"
    , "  o  m0/INIT/INV/inv0"
    , "  o  m0/INIT/WD"
    , "  o  m0/INIT/WWD"
    , "  o  m0/INV/WD"
    , " xxx m0/SKIP/CO/co0"
    , "  o  m0/TR/tr0/inc/EN"
    , "  o  m0/TR/tr0/inc/NEG"
    , "  o  m0/co0/CO/WD"
    , "  o  m0/inc/CO/co0"
    --, "  o  m0/inc/C_SCH/weaken/c0"
    , "  o  m0/inc/FIS/x@prime"
    , "  o  m0/inc/FIS/y@prime"
    , "  o  m0/inc/INV/inv0"
    , "  o  m0/inc/WD/ACT/a0"
    , "  o  m0/inc/WD/ACT/a1"
    , "  o  m0/inc/WD/C_SCH"
    , "  o  m0/inc/WD/F_SCH"
    , "  o  m0/inc/WD/GRD"
    , "  o  m0/inc/WWD"
    , "  o  m0/tr0/TR/WD"
    , "passed 20 / 21"
    ]

path3 :: String
path3 = "Tests/small_machine.tex"

case3 :: IO (String, Map Label Sequent)
case3 = verify path3 0

result4 :: String
result4 = unlines 
    [ "; m0/inc/INV/inv0"
    , "(set-option :auto-config false)"
    , "(set-option :smt.timeout 3000)"
    , "(declare-datatypes (a) ( (Maybe (Just (fromJust a)) Nothing) ))"
    , "(declare-datatypes () ( (Null null) ))"
    , "(declare-datatypes (a b) ( (Pair (pair (first a) (second b))) ))"
    , "; comment: we don't need to declare the sort Bool"
    , "; comment: we don't need to declare the sort Int"
    , "; comment: we don't need to declare the sort Real"
    , "(define-sort set (a) (Array a Bool))"
    , "(declare-const x Int)"
    , "(declare-const x@prime Int)"
    , "(declare-const y Int)"
    , "(declare-const y@prime Int)"
    , "; a0"
    , "(assert (= x@prime (+ x 2)))"
    , "; a1"
    , "(assert (= y@prime (+ y 1)))"
    , "; inv0"
    , "(assert (= x (* 2 y)))"
    , "(assert (not (= x@prime (* 2 y@prime))))"
    , "(check-sat-using (or-else (then qe smt)"
    , "                          (then simplify smt)"
    , "                          (then skip smt)"
    , "                          (then (using-params simplify :expand-power true) smt)))"
    , "; m0/inc/INV/inv0"
    ]

show_po :: FilePath -> Label -> IO String
show_po path lbl = proof_obligation path (show lbl) 0

case4 :: IO String
case4 = show_po path3 "m0/inc/INV/inv0"

result5 :: String
result5 = unlines 
    [ "; m0/SKIP/CO/co0"
    , "(set-option :auto-config false)"
    , "(set-option :smt.timeout 3000)"
    , "(declare-datatypes (a) ( (Maybe (Just (fromJust a)) Nothing) ))"
    , "(declare-datatypes () ( (Null null) ))"
    , "(declare-datatypes (a b) ( (Pair (pair (first a) (second b))) ))"
    , "; comment: we don't need to declare the sort Bool"
    , "; comment: we don't need to declare the sort Int"
    , "; comment: we don't need to declare the sort Real"
    , "(define-sort set (a) (Array a Bool))"
    , "(declare-const x Int)"
    , "(declare-const x@prime Int)"
    , "(declare-const y Int)"
    , "(declare-const y@prime Int)"
    , "; SKIP:x"
    , "(assert (= x@prime x))"
    , "; SKIP:y"
    , "(assert (= y@prime y))"
    , "; inv0"
    , "(assert (= x (* 2 y)))"
    , "(assert (not (=> (= x 2) (= x@prime 4))))"
    , "(check-sat-using (or-else (then qe smt)"
    , "                          (then simplify smt)"
    , "                          (then skip smt)"
    , "                          (then (using-params simplify :expand-power true) smt)))"
    , "; m0/SKIP/CO/co0"
    ]

case5 :: IO String
case5 = show_po path3 "m0/SKIP/CO/co0"

result6 :: String
result6 = unlines 
    [ "  o  m0/INIT/FIS/x"
    , "  o  m0/INIT/FIS/y"
    , "  o  m0/INIT/INV/inv0"
    , "  o  m0/INIT/WD"
    , "  o  m0/INIT/WWD"
    , "  o  m0/INV/WD"
    , " xxx m0/SKIP/CO/co0"
    , "  o  m0/TR/tr0/inc/EN"
    , "  o  m0/TR/tr0/inc/NEG"
    , "  o  m0/co0/CO/WD"
    , "  o  m0/inc/CO/co0"
    --, "  o  m0/inc/C_SCH/weaken/c0"
    , "  o  m0/inc/FIS/x@prime"
    , "  o  m0/inc/FIS/y@prime"
    , "  o  m0/inc/INV/inv0"
    , "  o  m0/inc/SCH/grd0"
    , "  o  m0/inc/WD/ACT/a0"
    , "  o  m0/inc/WD/ACT/a1"
    , "  o  m0/inc/WD/C_SCH"
    , "  o  m0/inc/WD/F_SCH"
    , "  o  m0/inc/WD/GRD"
    , "  o  m0/inc/WWD"
    , "  o  m0/tr0/TR/WD"
    , "passed 21 / 22"
    ]

path6 :: String
path6 = "Tests/small_machine_t3.tex"

case6 :: IO (String, Map Label Sequent)
case6 = verify path6 0

result7 :: String
result7 = unlines 
    [ "; m0/inc/SCH/grd0"
    , "(set-option :auto-config false)"
    , "(set-option :smt.timeout 3000)"
    , "(declare-datatypes (a) ( (Maybe (Just (fromJust a)) Nothing) ))"
    , "(declare-datatypes () ( (Null null) ))"
    , "(declare-datatypes (a b) ( (Pair (pair (first a) (second b))) ))"
    , "; comment: we don't need to declare the sort Bool"
    , "; comment: we don't need to declare the sort Int"
    , "; comment: we don't need to declare the sort Real"
    , "(define-sort set (a) (Array a Bool))"
    , "(declare-const x Int)"
    , "(declare-const y Int)"
    , "; c0"
    , "(assert (= x y))"
    , "; inv0"
    , "(assert (= x (* 2 y)))"
    , "(assert (not (= x y)))"
    , "(check-sat-using (or-else (then qe smt)"
    , "                          (then simplify smt)"
    , "                          (then skip smt)"
    , "                          (then (using-params simplify :expand-power true) smt)))"
    , "; m0/inc/SCH/grd0"
    ]

case7 :: IO String
case7 = show_po path6 "m0/inc/SCH/grd0"

path8 :: FilePath
path8 = "Tests/small_machine_t4.tex"

result8 :: String
result8 = unlines 
    [ "; m0/inc/SCH/grd0"
    , "(set-option :auto-config false)"
    , "(set-option :smt.timeout 3000)"
    , "(declare-datatypes (a) ( (Maybe (Just (fromJust a)) Nothing) ))"
    , "(declare-datatypes () ( (Null null) ))"
    , "(declare-datatypes (a b) ( (Pair (pair (first a) (second b))) ))"
    , "; comment: we don't need to declare the sort Bool"
    , "; comment: we don't need to declare the sort Int"
    , "; comment: we don't need to declare the sort Real"
    , "(define-sort set (a) (Array a Bool))"
    , "(declare-const x Int)"
    , "(declare-const y Int)"
    , "; c0"
    , "(assert (= x y))"
    --, "; default"
    --, "(assert false)"
    , "; inv0"
    , "(assert (= x (* 2 y)))"
    , "(assert (not (= x y)))"
    , "(check-sat-using (or-else (then qe smt)"
    , "                          (then simplify smt)"
    , "                          (then skip smt)"
    , "                          (then (using-params simplify :expand-power true) smt)))"
    , "; m0/inc/SCH/grd0"
    ]

case8 :: IO String
case8 = show_po path8 "m0/inc/SCH/grd0"

result9 :: String
result9 = unlines
    [ "; m0/inc/C_SCH/weaken/c0"
    , "(set-option :auto-config false)"
    , "(set-option :smt.timeout 3000)"
    , "(declare-datatypes (a) ( (Maybe (Just (fromJust a)) Nothing) ))"
    , "(declare-datatypes () ( (Null null) ))"
    , "(declare-datatypes (a b) ( (Pair (pair (first a) (second b))) ))"
    , "; comment: we don't need to declare the sort Bool"
    , "; comment: we don't need to declare the sort Int"
    , "; comment: we don't need to declare the sort Real"
    , "(define-sort set (a) (Array a Bool))"
    , "(declare-const x Int)"
    , "(declare-const x@prime Int)"
    , "(declare-const y Int)"
    , "(declare-const y@prime Int)"
    , "; default"
    , "(assert false)"
    , "; inv0"
    , "(assert (= x (* 2 y)))"
    , "(assert (not (= x y)))"
    , "(check-sat-using (or-else (then qe smt)"
    , "                          (then simplify smt)"
    , "                          (then skip smt)"
    , "                          (then (using-params simplify :expand-power true) smt)))"
    , "; m0/inc/C_SCH/weaken/c0"
    ]

case9 :: IO String
case9 = show_po path6 "m0/inc/C_SCH/weaken/c0"

result10 :: String
result10 = unlines 
    [ "; m0/TR/tr0/inc/EN"
    , "(set-option :auto-config false)"
    , "(set-option :smt.timeout 3000)"
    , "(declare-datatypes (a) ( (Maybe (Just (fromJust a)) Nothing) ))"
    , "(declare-datatypes () ( (Null null) ))"
    , "(declare-datatypes (a b) ( (Pair (pair (first a) (second b))) ))"
    , "; comment: we don't need to declare the sort Bool"
    , "; comment: we don't need to declare the sort Int"
    , "; comment: we don't need to declare the sort Real"
    , "(define-sort set (a) (Array a Bool))"
    , "(declare-const x Int)"
    , "(declare-const x@prime Int)"
    , "(declare-const y Int)"
    , "(declare-const y@prime Int)"
    , "; inv0"
    , "(assert (= x (* 2 y)))"
    , "(assert (not (=> (= x y) (= x y))))"
    , "(check-sat-using (or-else (then qe smt)"
    , "                          (then simplify smt)"
    , "                          (then skip smt)"
    , "                          (then (using-params simplify :expand-power true) smt)))"
    , "; m0/TR/tr0/inc/EN"
    ]

case10 :: IO String
case10 = show_po path6 "m0/TR/tr0/inc/EN"

result11 :: String
result11 = unlines
    [ "; m0/TR/tr0/inc/NEG"
    , "(set-option :auto-config false)"
    , "(set-option :smt.timeout 3000)"
    , "(declare-datatypes (a) ( (Maybe (Just (fromJust a)) Nothing) ))"
    , "(declare-datatypes () ( (Null null) ))"
    , "(declare-datatypes (a b) ( (Pair (pair (first a) (second b))) ))"
    , "; comment: we don't need to declare the sort Bool"
    , "; comment: we don't need to declare the sort Int"
    , "; comment: we don't need to declare the sort Real"
    , "(define-sort set (a) (Array a Bool))"
    , "(declare-const x Int)"
    , "(declare-const x@prime Int)"
    , "(declare-const y Int)"
    , "(declare-const y@prime Int)"
    , "; a0"
    , "(assert (= x@prime (+ x 2)))"
    , "; a1"
    , "(assert (= y@prime (+ y 1)))"
    , "; c0"
    , "(assert (= x y))"
    , "; grd0"
    , "(assert (= x y))"
    , "; inv0"
    , "(assert (= x (* 2 y)))"
    , "(assert (not (=> (= x y) (not (= x@prime y@prime)))))"
    , "(check-sat-using (or-else (then qe smt)"
    , "                          (then simplify smt)"
    , "                          (then skip smt)"
    , "                          (then (using-params simplify :expand-power true) smt)))"
    , "; m0/TR/tr0/inc/NEG"
    ]

case11 :: IO String
case11 = show_po path6 "m0/TR/tr0/inc/NEG"

var_x :: Var
var_y :: Var
x :: ExprP
y :: ExprP
x' :: ExprP
y' :: ExprP

(x,x',var_x) = prog_var "x" int
(y,y',var_y) = prog_var "y" int

c :: Ctx
c = ctx $ do
    primable $ do
        decls %= M.insert "x" var_x
        decls %= M.insert "y" var_y

vars :: Map String Var
vars = fromList [("x", var_x), ("y", var_y)]

inc_event_m0 :: Event
inc_event_m0 = empty_event { 
    _actions = fromList [
                ("a0",BcmSuchThat (M.elems vars) 
                    $ c $ [expr| x' = x+2 |] . (is_step .~ True)) ] }

inc_event_m1 :: Event
inc_event_m1 = empty_event 
        { _coarse_sched = singleton "c0" $ 
                                c [expr| x = y |]
        , _fine_sched = singleton "f0" $ 
                                c [expr| x = y |]
        , _actions = fromList [
                    ("a0",BcmSuchThat (M.elems vars) $ 
                            c $ [expr| x' = x + 2 |] . (is_step .~ True)),
                    ("a1",BcmSuchThat (M.elems vars) $ 
                            c $ [expr| y' = y + 1 |] . (is_step .~ True)) ] 
        }

m0_machine :: Machine
m0_machine = empty_machine "m0" & content assert %~ \m -> m
        & props .~ m0_props
        & event_table .~ newEvents [("inc", inc_event_m0)]
        & variables .~ vars 

m1_machine :: Machine
m1_machine = empty_machine "m0" & content assert %~ \m -> m
        & props .~ m1_props
        & event_table .~ newEvents [("inc",inc_event_m1)]
        & variables .~ vars
        

m0_props :: PropertySet
m0_props = empty_property_set {
        _inv = singleton "inv0" $
                c [expr| x = 2 \cdot y |] }

m1_props :: PropertySet
m1_props = m0_props
        { _transient = fromList [
            ("tr0", Tr M.empty (c [expr| x = y |]) (NE.fromList ["inc"]) empty_hint) ]
        , _constraint = fromList [
            ("co0", Co [] (c $ [expr| x = 1 \implies x' = 2 |] . (is_step .~ True))) ]
        , _inv = insert 
                "inv1" 
                (c [expr| x = x \cdot (y + 1) |])
                (_inv m0_props)
        }

path12 :: String
path12 = "Tests/small_machine_t12.tex"

case12 :: IO String
case12 = do
    find_errors path12

result12 :: String
result12 = unlines
    [ "Multiple expressions with the label c0"
    , "error 41:1:"
    , "\tcoarse schedule (event 'inc')"
    , ""
    , "error 46:1:"
    , "\tco property"
    , ""
    , ""
    ]
