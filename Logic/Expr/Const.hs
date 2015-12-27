{-# LANGUAGE ScopedTypeVariables #-}
module Logic.Expr.Const where

    -- Modules   
import Logic.Expr.Classes 
import Logic.Expr.Expr
import Logic.Expr.Genericity
import Logic.Expr.Type
import Logic.Names

    -- Libraries
import Control.Lens hiding (rewrite,Const)
import Control.Monad 

import           Data.Foldable as F
import           Data.List as L
import qualified Data.Map as M
import           Data.Maybe hiding ( fromJust )
import qualified Data.Set as S

import Utilities.Partial
import Utilities.Syntactic

infixr 1 .==.
infix 2 .=>
infixr 3 \/
infixr 3 /\
infix 4 .=.
infix 4 .<=
infix 4 .<
infixr 5 .+
infixr 6 .*
infixl 7 .^

type OneExpr n t q = AbsExpr n t q -> AbsExpr n t q

type TwoExpr n t q = AbsExpr n t q -> AbsExpr n t q -> AbsExpr n t q

fun1 :: ( TypeSystem t )
     => AbsFun n t 
     -> AbsExpr n t q -> AbsExpr n t q
fun1 f x           = FunApp f [x]
fun2 :: ( TypeSystem t  )
     => AbsFun n t -> AbsExpr n t q
     -> AbsExpr n t q -> AbsExpr n t q
fun2 f x y         = FunApp f [x,y]

no_errors2 :: ( TypeSystem t 
              , IsQuantifier q )
           => (TwoExprP n t q)
           -> (TwoExpr n t q)
no_errors2 f x y = either (error . unlines) id $ f (Right x) (Right y)

toErrors :: LineInfo -> ExprP -> Either [Error] Expr
toErrors li m = case m of
        Right x -> Right x
        Left xs -> Left $ map (`Error` li) xs

not_fun :: (TypeSystem2 t,IsName n) => AbsFun n t
not_fun = mk_fun [] (fromString'' "not") [bool] bool

znot :: (TypeSystem2 t, IsQuantifier q,IsName n) => OneExpr n t q
znot e = case e of 
            FunApp f [x]
                | f == not_fun -> x
                | otherwise    -> fun1 not_fun e
            e' -> fun1 not_fun e'
    -- znot         = fun1 mznot
zimplies :: (TypeSystem2 t, IsQuantifier q,IsName n) => TwoExpr n t q
zimplies x y = ($typeCheck) $ mzimplies (Right x) (Right y)
zand :: (TypeSystem2 t, IsQuantifier q,IsName n) => TwoExpr n t q
zand x y     = zall [x, y]
zor :: (TypeSystem2 t, IsQuantifier q,IsName n) => TwoExpr n t q
zor x y      = zsome [x, y]

zeq_fun :: IsName n => AbsFun n Type
zeq_fun      = mk_fun [] (fromString'' "=") [gA, gA] bool

zeq_symb :: (IsQuantifier q,IsName n) => TwoExpr n Type q
zeq_symb     = no_errors2 mzeq_symb
mzeq_symb :: IsName n => TwoExprP n Type q
mzeq_symb    = typ_fun2 $ mk_fun [gA] (fromString'' "eq") [gA, gA] bool

zeq :: (IsQuantifier q,IsName n)
    => AbsExpr n Type q -> AbsExpr n Type q -> AbsExpr n Type q
zeq          = no_errors2 mzeq
mzeq :: IsName n => TwoExprP n Type q
mzeq         = typ_fun2 zeq_fun

(.=.) :: IsName n => TwoExprP n Type q
(.=.) = mzeq
(.==.) :: IsName n => TwoExprP n Type q
(.==.) = mzeq

zfollows :: (IsName n,TypeSystem2 t) => AbsExpr n t q -> AbsExpr n t q -> AbsExpr n t q
zfollows     = fun2 $ mk_fun [] (fromString'' "follows") [bool,bool] bool
-- zfollows     = fun2 mzfollows
zall :: (TypeSystem2 t, IsQuantifier q, Foldable list,IsName n) 
     => list (AbsExpr n t q) -> AbsExpr n t q
zall xs'      = 
        case xs of
            []  -> ztrue
            [x] -> x
            xs  
                | zfalse `elem` xs -> zfalse
                | otherwise -> FunApp (mk_fun [] (fromString'' "and") (replicate n bool) bool) xs
    where
        xs = concatMap f $ F.toList xs'
        n = length xs
        f (FunApp fun@(Fun [] n _ _ _) xs)
            | render n == "and" 
                && not (isLifted fun) = concatMap f xs
        f x
            | x == ztrue = []
            | otherwise   = [x]
zsome :: (TypeSystem2 t, IsQuantifier q, Traversable list,IsName n) 
      => list (AbsExpr n t q) -> AbsExpr n t q
zsome xs'      = 
        case concatMap f xs of
            []  -> zfalse
            [x] -> x
            xs
                | ztrue `elem` xs -> ztrue
                | otherwise        -> FunApp (mk_fun [] (fromString'' "or") (replicate n bool) bool) xs
    where
        xs = toList xs'
        n = length xs
        f (FunApp fun@(Fun [] n _ _ _) xs) 
            | n == fromString'' "or"
                && not (isLifted fun) = concatMap f xs
        f x
            | x == zfalse = []
            | otherwise   = [x]
zforall :: (TypeSystem2 t, IsQuantifier q,IsName n)
        => [AbsVar n t] 
        -> AbsExpr n t q
        -> AbsExpr n t q
        -> AbsExpr n t q
zforall [] x y  = zimplies x y
zforall vs x w@(Binder q us y z _) 
    | q == qForall = if x == ztrue
            then zforall (vs ++ us) y z
            else Binder qForall vs x w bool
zforall vs x w   
    |    x `elem` [ztrue, zfalse]
      && w `elem` [ztrue, zfalse] = zimplies x w
    | otherwise                   = Binder qForall vs x w bool

zexists :: (TypeSystem2 t, IsQuantifier q,IsName n)
        => [AbsVar n t] 
        -> AbsExpr n t q
        -> AbsExpr n t q
        -> AbsExpr n t q
zexists [] x y = zand x y
zexists vs x w@(Binder q us y z _) 
    | q == qExists = if x == ztrue 
                        then zexists (vs ++ us) y z
                        else Binder qExists vs x w bool
zexists vs x w   
    |    x `elem` [ztrue, zfalse]
      && w `elem` [ztrue, zfalse] = zand x w
    | otherwise                   = Binder qExists vs x w bool

zquantifier :: HOQuantifier -> [Var] -> ExprP -> ExprP -> ExprP
zquantifier q vs r t = do
    r' <- zcast bool r
    t' <- zcast (termType q) t
    let tuple = ztuple_type (map var_type vs)
        rt    = exprType q tuple (type_of t')
    return $ Binder q vs r' t' rt

zite :: IsName n => ThreeExprP n Type q
zite       = typ_fun3 (mk_fun [] (fromString'' "ite") [bool,gA,gA] gA)

zjust :: IsName n => OneExprP n Type q
zjust      = typ_fun1 (mk_fun [] (fromString'' "Just") [gA] (maybe_type gA))

znothing :: IsName n => ExprPG n Type q
znothing   = Right $ Cast (FunApp (mk_fun [] (fromString'' "Nothing") [] $ maybe_type gA) []) (maybe_type gA)

mznot :: (TypeSystem2 t,IsName n) => OneExprP n t q
mznot me       = do
        e <- me
        case e of
            FunApp f [x] 
                | f == not_fun -> typ_fun1 not_fun (Right x)
            e -> typ_fun1 not_fun (Right e)
mzimplies :: (TypeSystem2 t,IsName n) => TwoExprP n t q
mzimplies mx my = do
        x <- mx
        y <- my
        if      x == ztrue  then Right y
        else if y == ztrue  then Right ztrue
        else if x == zfalse then Right ztrue
        else if y == zfalse then Right $ znot x
        else typ_fun2 implies_fun 
                (Right x) (Right y)

implies_fun :: (IsName n,TypeSystem t) => AbsFun n t
implies_fun = mk_fun [] (z3Name "=>") [bool,bool] bool

(.=>) :: (TypeSystem2 t,IsName n) => TwoExprP n t q
(.=>) = mzimplies

mzand :: (TypeSystem2 t,IsName n) => TwoExprP n t q
mzand x y     = mzall [x,y]
mzor :: (TypeSystem2 t,IsName n) => TwoExprP n t q
mzor x y      = mzsome [x,y]

(\/) :: (TypeSystem2 t,IsName n) => TwoExprP n t q
(\/) = mzor

(/\) :: (TypeSystem2 t,IsName n) => TwoExprP n t q
(/\) = mzand

mzfollows :: (TypeSystem2 t,IsName n) => TwoExprP n t q
mzfollows x y = mzimplies y x
mztrue :: (TypeSystem2 t,IsQuantifier q,IsName n)
       => ExprPG n t q
mztrue        = Right ztrue
mzfalse :: (TypeSystem2 t,IsQuantifier q,IsName n)
        => ExprPG n t q
mzfalse       = Right zfalse

mzall :: (IsQuantifier q, TypeSystem2 t, Traversable list,IsName n) 
      => list (ExprPG n t q) -> ExprPG n t q
mzall xs = case toList xs of
    []  -> mztrue
    [x] -> x
    xs  -> do
        xs <- forM xs $ zcast bool 
        return $ zall xs

mzsome :: (IsQuantifier q, TypeSystem2 t, Traversable list,IsName n) 
       => list (ExprPG n t q) -> ExprPG n t q
mzsome xs = case toList xs of
    []  -> mzfalse
    [x] -> x
    xs  -> do
        xs <- forM xs $ zcast bool
        return $ zsome xs

mzforall :: (TypeSystem2 t, IsQuantifier q,IsName n) 
         => [AbsVar n t] 
         -> TwoExprP n t q
mzforall xs mx my = do
        x <- zcast bool mx
        y <- zcast bool my
        return $ zforall xs x y

mzexists :: (TypeSystem2 t, IsQuantifier q,IsName n)
         => [AbsVar n t] 
         -> TwoExprP n t q
mzexists xs mx my = do
        x <- zcast bool mx
        y <- zcast bool my
        return $ zexists xs x y

zless :: (IsName n,TypeSystem2 t) => AbsExpr n t q -> AbsExpr n t q -> AbsExpr n t q
zless        = fun2 $ mk_fun [] (fromString'' "<") [int,int] bool

zgreater :: (IsName n,TypeSystem2 t) => AbsExpr n t q -> AbsExpr n t q -> AbsExpr n t q
zgreater     = fun2 $ mk_fun [] (fromString'' ">") [int,int] bool

le_fun :: (IsName n,TypeSystem t) => AbsFun n t
le_fun = mk_fun [] (z3Name "<=") [int,int] bool

zle :: (IsName n,TypeSystem2 t) => AbsExpr n t q -> AbsExpr n t q -> AbsExpr n t q
zle          = fun2 le_fun

zge :: (IsName n,TypeSystem2 t) => AbsExpr n t q -> AbsExpr n t q -> AbsExpr n t q
zge          = fun2 $ mk_fun [] (z3Name ">=") [int,int] bool

zplus :: (IsName n,TypeSystem2 t )=> AbsExpr n t q -> AbsExpr n t q -> AbsExpr n t q
zplus        = fun2 $ mk_fun [] (fromString'' "+") [int,int] int

zminus :: (IsName n,TypeSystem2 t )=> AbsExpr n t q -> AbsExpr n t q -> AbsExpr n t q
zminus       = fun2 $ mk_fun [] (fromString'' "-") [int,int] int

zopp :: (IsName n,TypeSystem2 t )=> AbsExpr n t q -> AbsExpr n t q
zopp         = fun1 $ mk_fun [] (fromString'' "-") [int] int

ztimes :: (IsName n,TypeSystem2 t )=> AbsExpr n t q -> AbsExpr n t q -> AbsExpr n t q
ztimes       = fun2 $ mk_fun [] (fromString'' "*") [int,int] int

zpow :: (IsName n,TypeSystem2 t )=> AbsExpr n t q -> AbsExpr n t q -> AbsExpr n t q
zpow         = fun2 $ mk_fun [] (fromString'' "^") [int,int] int

zselect :: IsName n => TwoExprP n Type q
zselect      = typ_fun2 (mk_fun [] (fromString'' "select") [array gA gB, gA] gB)

zint :: (TypeSystem2 t, Integral int) => int -> AbsExpr n t q
zint n       = Const (IntVal $ fromIntegral n) int

zreal :: TypeSystem2 t => Double -> AbsExpr n t q
zreal n      = Const (RealVal n) real

mzless :: (TypeSystem2 t,IsName n) => TwoExprP n t q
mzless        = typ_fun2 $ mk_fun [] (fromString'' "<") [int,int] bool
(.<) :: (TypeSystem2 t,IsName n) => TwoExprP n t q
(.<) = mzless

mzgreater :: (TypeSystem2 t,IsName n) => TwoExprP n t q
mzgreater        = typ_fun2 $ mk_fun [] (fromString'' ">") [int,int] bool
mzle :: (TypeSystem2 t,IsName n) => TwoExprP n t q
mzle          = typ_fun2 $ mk_fun [] (z3Name "<=") [int,int] bool
(.<=) :: (TypeSystem2 t,IsName n) => TwoExprP n t q
(.<=) = mzle

mzge :: (TypeSystem2 t,IsName n) => TwoExprP n t q
mzge          = typ_fun2 $ mk_fun [] (z3Name ">=") [int,int] bool
mzplus :: (TypeSystem2 t,IsName n) => TwoExprP n t q
mzplus       = typ_fun2 $ mk_fun [] (fromString'' "+") [int,int] int
(.+) :: (TypeSystem2 t,IsName n) => TwoExprP n t q
(.+)       = mzplus

mzminus :: (TypeSystem2 t,IsName n) => TwoExprP n t q
mzminus       = typ_fun2 $ mk_fun [] (fromString'' "-") [int,int] int
mzopp :: (TypeSystem2 t,IsQuantifier q,IsName n) => ExprPG n t q -> ExprPG n t q
mzopp         = typ_fun1 $ mk_fun [] (fromString'' "-") [int] int
mztimes :: (TypeSystem2 t,IsName n) => TwoExprP n t q
mztimes       = typ_fun2 $ mk_fun [] (fromString'' "*") [int,int] int
(.*) :: (TypeSystem2 t,IsName n) => TwoExprP n t q
(.*) = mztimes

mzpow :: (TypeSystem2 t,IsName n) => TwoExprP n t q
mzpow         = typ_fun2 $ mk_fun [] (fromString'' "^") [int,int] int
(.^) :: (TypeSystem2 t,IsName n) => TwoExprP n t q
(.^) = mzpow

mzint :: (TypeSystem2 t, Integral int) => int -> ExprPG n t q 
mzint n       = Right $ zint n

mzreal :: TypeSystem2 t => Int -> ExprPG n t q
mzreal x       = Right $ zreal $ fromIntegral x

mzpair :: ExprP -> ExprP -> ExprP
mzpair = typ_fun2 $ mk_fun [] (fromString'' "pair") [gA,gB] (pair_type gA gB)

var_of :: AbsExpr n t q -> AbsVar n t
var_of (Word v) = v
var_of _ = error "var_of: expecting a variable expression"

-- {-# DEPRECATED var, prog_var "use Logic.Expr.QuasiQuote" #-}
var :: (?loc :: CallStack,IsName n) => String -> t -> (Either a (AbsExpr n t q), AbsVar n t)
var n t      = (Right $ Word $ v, v)
    where
        v = Var (z3Name n) t

prog_var :: String -> Type -> (Either a Expr, Either a Expr, Var)
prog_var n t = (Right $ Word v, Right $ Word $ prime v, v)
    where
        v = Var (fromString'' n) t

zapply :: ExprP -> ExprP -> ExprP
zapply  = typ_fun2 (mk_fun [gA,gB] (fromString'' "apply") [fun_type gA gB, gA] gB)

one_point_rule :: forall n t q. (IsQuantifier q, TypeSystem2 t,IsName n) 
               => AbsExpr n t q -> AbsExpr n t q
one_point_rule (Binder q vs r t _) 
        | q == qExists = e
    where
        e  = zsome [ f $ zexists (filter (`S.member` fv) vs \\ M.keys inst) ztrue 
                        $ zall $ map (substitute 
                                        $ M.mapKeys (view name) inst) ts
                   | (inst,ts,fv) <- insts ]
        
        insts :: [ ( M.Map (AbsVar n t) (AbsExpr n t q)
                   , [AbsExpr n t q]
                   , S.Set (AbsVar n t)) ]
        insts = [ (M.unions $ map subst ts,ts,S.unions $ map used_var ts) | ts <- ts' ]
        
        subst :: AbsExpr n t q -> M.Map (AbsVar n t) (AbsExpr n t q)
        subst (FunApp f xs)
                | (z3_name f) == fromString'' "=" = M.fromList $ rs
            where
                rs = do (i,j) <- [(0,1),(1,0)]
                        k <- maybeToList 
                            $ (xs ! i) `lookup` zip (map Word vs) vs
                        guard $ S.null $ S.intersection (S.fromList vs) (used_var $ xs ! j)
                        return (k, xs ! j)
        subst _ = M.empty
        f x
            | length ts' == 1   = rewrite one_point_rule x
            | otherwise         = one_point_rule x
        ts = conjuncts r ++ conjuncts t
        ts' = forM (map disjuncts ts) id
one_point_rule e = rewrite one_point_rule e

conjuncts :: (IsName n,TypeSystem t) => AbsExpr n t q -> [AbsExpr n t q]
conjuncts (FunApp f xs) 
    | z3_name f == fromString'' "and" = xs
conjuncts x = [x]

disjuncts :: (IsName n,TypeSystem2 t) => AbsExpr n t q -> [AbsExpr n t q]
disjuncts (FunApp f xs)
    | z3_name f == fromString'' "or" = xs
    -- | name f == "=>"  = map znot (take 1 xs) ++ drop 1 xs
disjuncts x = [x]

zlift :: TypeSystem2 t => t -> AbsExpr n t q -> AbsExpr n t q
zlift t e = Lift e t

const_fun :: IsName n => AbsFun n Type
const_fun = mk_fun [gA,gB] (fromString'' "const") [gB] (array gA gB)

zconst :: ExprP -> ExprP
zconst = typ_fun1 const_fun

ident_fun :: IsName n => AbsFun n Type
ident_fun = mk_fun [gA] (fromString'' "ident") [] (array gA gA)

zelem        = typ_fun2 (mk_fun' [gA] "elem" [gA,set_type gA] bool)
zelem         :: (IsQuantifier q,IsName n) 
              => ExprPG n Type q -> ExprPG n Type q -> ExprPG n Type q

zident :: ExprP
zident = Right $ FunApp ident_fun []

instance Num ExprP where
    (-) = mzminus
    (+) = mzplus
    (*) = mztimes
    abs = typ_fun1 $ mk_fun [] (fromString'' "abs") [int] int
    signum x = zite (x .< 0) (-1) $ zite (0 .< x) 1 0
    fromInteger = mzint
    negate = mzopp

