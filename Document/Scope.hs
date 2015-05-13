{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE RankNTypes,TupleSections  #-}
{-# LANGUAGE ScopedTypeVariables       #-}
{-# LANGUAGE DefaultSignatures         #-}
{-# LANGUAGE MultiParamTypeClasses     #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE TypeFamilies              #-}
{-# LANGUAGE FunctionalDependencies    #-}
{-# LANGUAGE FlexibleInstances         #-}
{-# LANGUAGE TemplateHaskell           #-}
{-# LANGUAGE UndecidableInstances      #-}
module Document.Scope 
    ( Scope(..)
    , HasDeclSource (..)
    , HasLineInfo (..)
    , HasInhStatus (..)
    , make_table
    , make_all_tables 
    , make_all_tables'
    , all_errors
    , fromEither'
    , is_inherited, is_local
    , DeclSource(..)
    , InhStatus(..)
    , contents
    , WithDelete 
    )
where

    -- Modules
import Document.Pipeline

import UnitB.Event

    -- Libraries
import Control.Applicative

import Control.Lens as L 
import Control.Monad.Identity
import Control.Monad.RWS
import Control.Parallel.Strategies

import Data.Either
import Data.List as L
import Data.Map as M
import qualified Data.Traversable as T

import Utilities.Syntactic
import Utilities.Permutation

    -- clashes is a symmetric, reflexive relation
class (Ord a) => Scope a where
    type Impl a :: *
    type Impl a = DefaultClashImpl a
    error_item :: a -> (String,LineInfo)
    default error_item :: (Show a, HasLineInfo a LineInfo) => a -> (String,LineInfo)
    error_item x = (show x, view lineInfo x)

    keep_from :: DeclSource -> a -> Maybe a
    default keep_from :: (ClashImpl (Impl a), HasImplIso (Impl a) a) 
                      => DeclSource -> a -> Maybe a
    keep_from s x = (asImpl :: Iso' a (Impl a)) (keepFromImpl s) x

    make_inherited :: a -> Maybe a
    default make_inherited :: (ClashImpl (Impl a), HasImplIso (Impl a) a) 
                           => a -> Maybe a
    make_inherited x = (asImpl :: Iso' a (Impl a)) makeInheritedImpl x

    clashes :: a -> a -> Bool
    default clashes :: (ClashImpl (Impl a), HasImplIso (Impl a) a) => a -> a -> Bool
    clashes x y = clashesImpl (x ^. asImpl :: Impl a) (y ^. asImpl)

    merge_scopes :: a -> a -> a
    default merge_scopes :: (ClashImpl (Impl a), HasImplIso (Impl a) a) => a -> a -> a
    merge_scopes x y = mergeScopesImpl (x ^. asImpl :: Impl a) (y ^. asImpl) ^. L.from asImpl

    rename_events :: Map EventId [EventId] -> a -> [a]
    rename_events _ x = [x]

newtype DefaultClashImpl a = DefaultClashImpl { getDefaultClashImpl :: a }

class HasImplIso a b where
    asImpl :: Iso' b a

class ClashImpl a where
    clashesImpl :: a -> a -> Bool
    mergeScopesImpl :: a -> a -> a
    keepFromImpl :: DeclSource -> a -> Maybe a
    makeInheritedImpl :: a -> Maybe a

instance HasDeclSource a DeclSource 
        => ClashImpl (DefaultClashImpl a) where
    keepFromImpl s x'@(DefaultClashImpl x) = guard (x ^. declSource == s) >> return x'
    makeInheritedImpl (DefaultClashImpl x) = Just $ DefaultClashImpl $ x & declSource .~ Inherited
    clashesImpl _ _ = True
    mergeScopesImpl _ _ = error "merging clashing scopes"

instance HasImplIso (DefaultClashImpl a) a where
    asImpl = iso DefaultClashImpl getDefaultClashImpl

class HasDeclSource a b | a -> b where
    declSource :: Lens' a b

class HasLineInfo a b | a -> b where
    lineInfo :: Lens' a b

class HasInhStatus a b | a -> b where
    inhStatus :: Lens' a b

is_inherited :: Scope s => s -> Maybe s
is_inherited = keep_from Inherited

is_local :: Scope s => s -> Maybe s
is_local = keep_from Local

data DeclSource = Inherited | Local
    deriving (Eq,Ord,Show)

data InhStatus a = InhAdd a | InhDelete (Maybe a)
    deriving (Eq,Ord)

contents :: HasInhStatus a (InhStatus b) => a -> Maybe b
contents x = case x ^. inhStatus of
                InhAdd x -> Just x
                InhDelete x -> x

fromEither' :: Either [Error] a -> MM (Maybe a)
fromEither' (Left es) = tell es >> return Nothing
fromEither' (Right x) = return $ Just x

all_errors :: Traversable t 
           => t (Either [Error] a) 
           -> MM (Maybe (t a))
all_errors m = T.mapM fromEither' m >>= (return . T.sequence)

make_table :: (Ord a, Show a) 
           => (a -> String) 
           -> [(a,b,LineInfo)] 
           -> Either [Error] (Map a (b,LineInfo))
make_table f xs = returnOrFail $ fromListWith add $ L.map mkCell xs
    where
        mkCell (x,y,z) = (x,Right (y,z))
        sepError (x,y) = case y of
                 Left z -> Left (x,z)
                 Right (z,li) -> Right (x,(z,li))
        returnOrFail m = failIf $ L.map sepError $ M.toList m
        failIf xs 
            | L.null ys = return $ M.fromList $ rights xs
            | otherwise = Left $ L.map (uncurry err) ys
            where
                ys = lefts xs
        err x li = MLError (f x) (L.map (show x,) li)
        lis (Left xs)     = xs
        lis (Right (_,z)) = [z]
        add x y = Left $ lis x ++ lis y

make_all_tables' :: (Scope b, Show a, Ord a, Ord k) 
                 => (a -> String) 
                 -> Map k [(a,b)] 
                 -> MM (Maybe (Map k (Map a b)))
make_all_tables' f xs = T.sequence <$> T.sequence (M.map (make_table' f) xs `using` parTraversable rseq)

make_all_tables :: (Show a, Ord a, Ord k) 
                => (a -> String)
                -> Map k [(a, b, LineInfo)] 
                -> MM (Maybe (Map k (Map a (b,LineInfo))))
make_all_tables f xs = all_errors (M.map (make_table f) xs `using` parTraversable rseq)

make_table' :: forall a b.
               (Ord a, Show a, Scope b) 
            => (a -> String) 
            -> [(a,b)] 
            -> MM (Maybe (Map a b))
make_table' f xs = all_errors $ M.mapWithKey g ws
    where
        g k ws
                | all (\xs -> length xs <= 1) ws 
                            = Right $ L.foldl merge_scopes (head xs) (tail xs)
                | otherwise = Left $ L.map (\xs -> MLError (f k) $ L.map error_item xs) 
                                    $ L.filter (\xs -> length xs > 1) ws
            where
                xs = concat ws             
        zs = fromListWith (++) $ L.map (\(x,y) -> (x,[y])) xs
        ws :: Map a [[b]]
        ws = M.map (flip u_scc clashes) zs 

data WithDelete a = WithDelete a

instance HasImplIso (WithDelete a) a where
    asImpl = iso WithDelete (\(WithDelete x) -> x)

instance ( HasInhStatus a (InhStatus expr)
         , HasDeclSource a DeclSource )
        => ClashImpl (WithDelete a) where
    makeInheritedImpl (WithDelete x) = Just $ WithDelete $ x & declSource .~ Inherited
    keepFromImpl s (WithDelete x) = guard b >> return (WithDelete x)
        where
            b = case x ^. inhStatus of
                    InhAdd _ -> x ^. declSource == s
                    InhDelete _  -> s == Inherited
    clashesImpl (WithDelete x) (WithDelete y) = f x == f y
        where
            f x = case x ^. inhStatus :: InhStatus expr of 
                    InhAdd _ -> True
                    InhDelete (Just _) -> True
                    InhDelete Nothing -> False

    mergeScopesImpl (WithDelete x) (WithDelete y) = WithDelete z
        where
            z = case (x ^. inhStatus, y ^. inhStatus) of
                    (InhDelete Nothing, InhAdd e) -> x & inhStatus .~ InhDelete (Just e)
                    (InhAdd e, InhDelete Nothing) -> y & inhStatus .~ InhDelete (Just e)
                    _ -> error "WithDelete ClashImpl.merge_scopes: Evt, Evt"