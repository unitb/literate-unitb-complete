{-# LANGUAGE TypeFamilies,GADTs #-}
module Logic.Expr.Classes where

import Logic.Names

import Control.Lens hiding (List,rewriteM)
import Control.Monad.Reader
import Control.Monad.State

import Data.Data
import Data.Data.Lens 
import Data.Foldable as F
import Data.List as L 
import Data.Tuple
import Data.Typeable.Lens

import Utilities.Map  as M
import Utilities.Table as M

class HasName a n | a -> n where
    name :: Getter a n

as_pair :: HasName a n 
        => a -> (n, a)
as_pair = as_pair' id

as_pair' :: HasName b n 
         => (a -> b) -> a -> (n, a)
as_pair' f n = (f n^.name, n)

class (IsName (NameOf n), HasName n (NameOf n), Typeable n, Show (NameOf n)) => Named n where
    type NameOf n :: *
    decorated_name :: n -> InternalName
    decorated_name x = runReader (decorated_name' x) ProverOutput

    decorated_name' :: n -> Reader (OutputMode n0) n0

    z3_name :: n -> InternalName
    z3_name x = x^.name.to asInternal

data OutputMode :: * -> * where 
    ProverOutput :: OutputMode InternalName
    UserOutput :: OutputMode Name

adaptName :: (IsName n,MonadReader (OutputMode n0) m) 
          => n -> m n0
adaptName n = do
    mode <- ask
    return $ case mode of
        ProverOutput -> asInternal n
        UserOutput -> asName n

onOutputName :: (MonadReader (OutputMode n) m) 
             => (forall n0. IsName n0 => n0 -> a)
             -> m n -> m a
onOutputName f m = do
    mode <- ask
    x    <- m
    return $ case mode of
        ProverOutput -> f x
        UserOutput -> f x

onInternalName :: (MonadReader (OutputMode n) m) 
             => (InternalName -> InternalName)
             -> m n -> m n
onInternalName f m = do
    mode <- ask
    x    <- m
    return $ case mode of
        ProverOutput -> f x
        UserOutput -> x

render_decorated :: Named n0 => n0 -> Reader (OutputMode n) String
render_decorated = onOutputName render . decorated_name'

class Tree a where
    as_tree   :: a -> StrList
    as_tree'  :: a -> Reader (OutputMode n) StrList
    as_tree x = runReader (as_tree' x) ProverOutput
    rewrite'  :: (b -> a -> (b,a)) -> b -> a -> (b,a)
    rewriteM :: (Applicative m, Tree a) => (a -> m a) -> a -> m a
    default rewriteM :: (Applicative m, Data a) => (a -> m a) -> a -> m a
    rewriteM f t = gtraverse (_cast f) t

    rewrite' f x t = (rewriteM' g x t) ()
        where
            g x t () = f x t

rewriteM' :: (Monad m, Tree a) => (b -> a -> m (b,a)) -> b -> a -> m (b,a)
rewriteM' f x t = swap <$> runStateT (rewriteM (StateT . fmap (fmap swap) . flip f) t) x

instance Tree () where
    as_tree' () = return $ List []
    rewriteM f = f

data StrList = List [StrList] | Str String

instance Show StrList where
    show (List xs) = "(" ++ intercalate " " (L.map show xs) ++ ")"
    show (Str s)   = s

fold_mapM :: Monad m => (a -> b -> m (a,c)) -> a -> [b] -> m (a,[c])
fold_mapM _ s [] = return (s,[])
fold_mapM f s0 (x:xs) = do
        (s1,y)  <- f s0 x
        (s2,ys) <- fold_mapM f s1 xs
        return (s2,y:ys)

fold_map :: (a -> b -> (a,c)) -> a -> [b] -> (a,[c])
fold_map _ s [] = (s,[])
fold_map f s0 (x:xs) = (s2,y:ys)
    where
        (s1,y)  = f s0 x
        (s2,ys) = fold_map f s1 xs

visit :: Tree a => (b -> a -> b) -> b -> a -> b
visit f s x = fst $ rewrite' g s x
    where
        g s0 y = (f s0 y, y)

rewrite :: Tree a => (a -> a) -> a -> a
rewrite f x = snd $ rewrite' g () x
    where
        g () x = ((), f x)

visitM :: (Monad m, Tree a) => (b -> a -> m b) -> b -> a -> m b
visitM f x t = visit g (return x) t
    where
        g x t = do
            y <- x
            f y t

children :: Tree a => Traversal' a a
children = rewriteM

class FromList a b where
    from_list :: a -> [b] -> b

instance FromList a a where
    from_list x [] = x
    from_list _ _  = error "from_list: too many arguments"

instance FromList a b => FromList (b -> a) b where
    from_list f (x:xs) = from_list (f x) xs
    from_list _ [] = error "from_list: not enough arguments"

z3_escape :: String -> InternalName
z3_escape = fromString''

insert_symbol :: IsKey Table n => HasName a n => a -> Table n a -> Table n a
insert_symbol x = M.insert (x^.name) x

symbol_table' :: (HasName b n, Foldable f,IsKey Table n) 
              => (a -> b) -> f a -> Table n a
symbol_table' f xs = fromList $ L.map (as_pair' f) $ F.toList xs

symbol_table :: (HasName a n, Foldable f,M.IsKey Table n) 
             => f a -> Table n a
symbol_table = symbol_table' id

decorated_table :: Named a => [a] -> Table InternalName a
decorated_table xs = fromList $ L.map (\x -> (decorated_name x, x)) xs

renameAll' :: (HasNames a n0,IsName n1,HasName (SetNameT n1 a) n1)
           => (a -> SetNameT n1 a)
           -> Table n0 a -> Table n1 (SetNameT n1 a)
renameAll' f = symbol_table . (traverse %~ f) . M.elems

renameAll :: (HasNames a n0,IsName n1,HasName (SetNameT n1 a) n1)
          => (n0 -> n1)
          -> Table n0 a -> Table n1 (SetNameT n1 a)
renameAll f = renameAll' (namesOf %~ f)