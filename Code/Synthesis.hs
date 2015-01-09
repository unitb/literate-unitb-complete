{-# LANGUAGE TupleSections #-}
module Code.Synthesis where

    -- Modules
import Logic.Expr

import Theories.SetTheory

import           UnitB.AST as UB hiding (Event)
import qualified UnitB.AST as UB 

    -- Libraries
import Control.Monad
import Control.Monad.Trans
import Control.Monad.Trans.RWS

import Data.Maybe
import Data.List as L hiding (inits)
import Data.Map as M
-- import Data.Set

import Utilities.Format

data Program = 
        Event Label 
            -- 
        | Conditional [Expr] [(Expr, Program)]
            -- Precondition, list of branches
        | Sequence          [([Expr], Expr, Program)]
            -- Precondition, list of guarded programs
        | Loop    Expr [Expr] Program Termination
            -- Exit Invariant Body Termination

data Termination = Infinite | Finite

type M = RWST Int [String] () (Either String)

precondition :: Machine -> Program -> [Expr]
precondition m (Event evt) = M.elems $ guards $ events m ! evt
precondition _ (Conditional pre _) = pre
precondition _ (Sequence ((pre,_,_):_)) = pre
precondition _ (Sequence [])       = []
precondition _ (Loop _ inv _ _)    = inv
-- precondition _ (InfLoop _ inv _)   = inv

default_cfg :: Machine -> Program
default_cfg m = Loop g [] body Infinite
    where
        all_guard e = zall $ M.elems $ coarse $ new_sched e
        g    = zsome $ L.map (znot . all_guard) $ M.elems $ events m
        body = Sequence 
            $ L.map (\(lbl,e) -> ([],all_guard e,Event lbl)) 
            $ M.toList $ events m

emit :: String -> M ()
emit xs = do
    n <- ask
    forM_ (lines xs) $ \ln -> 
        tell [replicate n ' ' ++ ln]

emitAll :: [String] -> M ()
emitAll = mapM_ emit

indent :: Int -> M a -> M a
indent n = local (n+)

type_code :: Type -> Either String String
type_code t = 
            case t of
                Gen (USER_DEFINED s [])
                    | s == IntSort ->  return "Int"
                    | s == BoolSort -> return "Bool"
                Gen (USER_DEFINED s [t])
                    | s == set_sort -> do
                        c <- type_code t
                        return $ format "S.Set ({0})" c
                Gen (USER_DEFINED s [t0,t1])
                    | s == fun_sort -> do
                        c0 <- type_code t0
                        c1 <- type_code t1
                        return $ format 
                            "M.Map ({0}) ({1})" c0 c1
                _ -> Left $ format "unrecognized type: {0}" t
                    
eval_expr :: Machine -> Expr -> M String
eval_expr m e =
        case e of
            Word (Var n _)
                | n `M.member` variables m -> return $ "v_" ++ n
                | otherwise              -> return $ "c_" ++ n
            Const n _    -> return $ show n
            FunApp f [] 
                | name f == "empty-fun" -> return "M.empty"
                | name f == "empty-set" -> return "S.empty"
            FunApp f0 [e0,FunApp f1 [e1,e2]] 
                | name f0 == "ovl" && name f1 == "mk-fun" -> do
                    c0 <- eval_expr m e0
                    c1 <- eval_expr m e1
                    c2 <- eval_expr m e2
                    return $ format "(M.insert {1} {2} {0})" c0 c1 c2
            FunApp f [e]
                | name f == "not" -> do
                    c <- eval_expr m e
                    return $ format "(not {0})" c
            FunApp f [e0,e1] 
                | name f == "=" -> do
                    c0 <- eval_expr m e0
                    c1 <- eval_expr m e1
                    return $ format "({0} == {1})" c0 c1
                | name f == "+" -> do
                    c0 <- eval_expr m e0
                    c1 <- eval_expr m e1
                    return $ format "({0} + {1})" c0 c1
                | name f == "<" -> do
                    c0 <- eval_expr m e0
                    c1 <- eval_expr m e1
                    return $ format "({0} < {1})" c0 c1
                | name f == "ovl" -> do
                    c0 <- eval_expr m e0
                    c1 <- eval_expr m e1
                    return $ format "(M.union {0} {1})" c0 c1
                | name f == "mk-fun" -> do
                    c0 <- eval_expr m e0
                    c1 <- eval_expr m e1
                    return $ format "(M.singleton {0} {1})" c0 c1
            _ -> report $ format "unrecognized expression: {0}" e

struct :: Machine -> M ()
struct m = do
        code <- lift $ attr
        emit $ "data State = State\n    { " ++ code ++ " }"
    where
        attr = do 
            code <- mapM decl $ 
                           L.map ("v",) (M.elems $ variables m) 
            return $ intercalate "\n    , " code
        decl (pre,Var y t) = do
            code <- type_code t
            return $ format "{2}_{0} :: {1}" y code (pre :: String)

assign_code :: Machine -> Action -> M String
assign_code m (Assign v e) = do
        c0 <- eval_expr m e
        return $ format "v_{0} = {1}" (name v) c0
assign_code _ act@(BcmSuchThat _ _) = report $ format "Action is non deterministic: {0}" act
assign_code _ act@(BcmIn _ _) = report $ format "Action is non deterministic: {0}" act

init_value_code :: Machine -> Expr -> M [String]
init_value_code m e =
        case e of
            FunApp f [Word (Var n _),e0]
                    |      n `M.member` variables m 
                        && name f == "=" -> do
                                c0 <- eval_expr m e0
                                return [format "v_{0} = {1}" n c0]
            FunApp f es
                    | name f == "and" -> do
                        rs <- mapM (init_value_code m) es
                        return $ concat rs
            _ -> report $ format "initialization is not in a canonical form: {0}" e

event_body_code :: Machine -> UB.Event -> M ()
event_body_code m e = do
        acts <- mapM (assign_code m) $ M.elems $ actions e
        emit "modify $ \\s'@(State { .. }) ->"
        indent 2 $ do
            case acts of 
                x:xs -> do
                    emit $ format "s' { {0}" x
                    indent 3 $ do
                        mapM_ (emit . (", " ++)) xs
                        emit "}"
                []   -> emit "s'"

report :: String -> M a
report = lift . Left

event_code :: Machine -> UB.Event -> M ()
event_code m e = do
        unless (M.null $ params e) $ report "non null number of parameters"
        unless (M.null $ indices e) $ report "non null number of indices"
        unless (isNothing $ fine $ new_sched e) $ report "event has a fine schedule"
        grd  <- eval_expr m $ zall $ M.elems $ coarse $ new_sched e
        emit $ format "if {0} then" grd
        indent 2 $ event_body_code m e
        emit $ "else return ()"

init_code :: Machine -> M ()
init_code m = do
        acts <- liftM concat $ mapM (init_value_code m) $ M.elems $ inits m
        emit "s' = State"
        indent 5 $ do
            emitAll $ zipWith (++) ("{ ":repeat ", ") acts
            when (not $ L.null acts) 
                $ emit "}"

write_cfg :: Machine -> Program -> M ()
write_cfg m (Event lbl)          = do
    emit "(State { .. }) <- get"
    event_body_code m (events m ! lbl)
write_cfg m (Conditional _ ((c,b):cs)) = do
    emit "(State { .. }) <- get"
    expr <- eval_expr m c
    emit $ format "if {0} then do" expr
    indent 2 $ write_cfg m b
    forM_ cs $ \(c,b) -> do
        expr <- eval_expr m c
        emit $ format "else if {0} then do" expr
        indent 2 $ write_cfg m b
    emit $ format "else fail \"incomplete conditional\""
write_cfg _ (Conditional _ []) = emit "fail \"incomplete conditional\""
write_cfg m (Sequence xs) = do
    forM_ xs $ \(_p,g,b) -> do
        emit "(State { .. }) <- get"
        expr <- eval_expr m g
        emit $ format "if {0} then do" expr
        indent 2 $ write_cfg m b
        emit $ format "else return ()"
write_cfg m (Loop exit _inv b _) = do
    emit "fix $ \\proc' -> do"
    indent 2 $ do
        emit "(State { .. }) <- get"
        exitc <- eval_expr m exit
        emit $ format "if {0} then return ()" exitc
        emit "else do"
        indent 2 $ do
            write_cfg m b
            emit "proc'"
-- emit "(State { .. }) <- get"
--             exitc <- eval_expr m exit
--             emit $ format "if {0} then return ()" exitc
--             emit "else do"
--             indent 2 $ do
--                 mapM (event_code m) $ M.elems $ events m
--                 emit "proc'"

machine_code :: String -> Machine -> Expr -> M ()
machine_code name m _exit = do
        let args = concatMap (" c_" ++) $ M.keys $ consts $ theory m
            cfg  = default_cfg m
        emit $ format "{0}{1} = flip execState s' $" name args
        indent 22 $ do
            write_cfg m cfg
        indent 4 $ do
            emit "where"
            indent 4 $ init_code m

run :: M () -> Either String String
run cmd = liftM (unlines . snd) $ execRWST cmd 0 ()

source_file :: String -> Machine -> Expr -> Either String String
source_file name m exit = 
        run $ do
            emitAll 
                [ "{-# LANGUAGE RecordWildCards #-}"
                , "import Data.Map as M"
                , "import Data.Set as S"
                , "import Control.Monad.State"
                , "\n"
                ]
            struct m
            emit "\n"
            machine_code name m exit