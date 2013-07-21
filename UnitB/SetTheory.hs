module UnitB.SetTheory where

import Control.Monad

import Data.List as L
import Data.Map as M hiding ( foldl ) 

import UnitB.Theory

import Z3.Z3

set_sort = Sort "\\set" "set" 1
set_type t = USER_DEFINED set_sort [t]

set_theory :: Type -> Theory 
set_theory t = Theory [] types funs empty facts empty
    where
        types = symbol_table [set_sort]
        set_type = USER_DEFINED set_sort [t]
        funs = M.insert (dec "union") (Fun (dec "bunion") [set_type,set_type] set_type) $
            symbol_table [
                Fun (dec "elem") [t,set_type] BOOL,
                Fun (dec "set-diff") [set_type,set_type] set_type,
                Fun (dec "mk-set") [t] set_type ]
        facts = fromList 
                [ (label $ dec "0", axm0)
                , (label $ dec "1", axm1)
                ]
        Just axm0 = mzforall [x_decl,y_decl] ((x `zelem` zmk_set y) `mzeq` (x `mzeq` y))
        Just axm1 = mzforall [x_decl,s1_decl,s2_decl] (
                          (x `zelem` (s1 `zsetdiff` s2)) 
                    `mzeq` ( (x `zelem` s1) `mzand` mznot (x `zelem` s2) ))
        (x,x_decl) = var "x" t
        (y,y_decl) = var "y" t
        (s1,s1_decl) = var "s1" set_type
        (s2,s2_decl) = var "s2" set_type
        dec x = x ++ z3_decoration t
--            Fun 
        
zelem x y    = typed_fun2 (\t0 s0 -> do
                            t1 <- item_type s0
                            guard (t0 == t1)
                            return $ Fun (dec "elem" t0) [t0, SET t1] BOOL) x y
zsetdiff     = typed_fun2 $ (\s0 s1 -> do
                            t0 <- item_type s0
                            t1 <- item_type s1
                            guard ( t0 == t1 )
                            return $ Fun (dec "set-diff" t0) [s0,s0] s0)
zunion       = typed_fun2 $ (\s0 s1 -> do
                            t0 <- item_type s0
                            t1 <- item_type s1
                            guard ( t0 == t1 )
                            return $ Fun (dec "bunion" t0) [s0,s0] s0)
zmk_set      = typed_fun1 $ (\t0 -> let s0 = set_type t0 in
                            return $ Fun (dec "mk-set" t0) [s0,s0] s0)
zset_enum xs = foldl zunion y ys 
    where
        (y:ys) = L.map zmk_set xs

dec x t = x ++ z3_decoration t

item_type (USER_DEFINED s [t]) 
        | s == set_sort         = Just t
        | otherwise             = Nothing
item_type _                     = Nothing