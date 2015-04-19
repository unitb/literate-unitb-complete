{-# LANGUAGE ExistentialQuantification      #-}
{-# LANGUAGE RankNTypes,DeriveDataTypeable  #-}
{-# LANGUAGE TemplateHaskell,MultiParamTypeClasses   #-}
{-# LANGUAGE FunctionalDependencies,FlexibleContexts #-}
{-# LANGUAGE TypeSynonymInstances,FlexibleInstances  #-}
{-# LANGUAGE TypeFamilies, DefaultSignatures  #-}
module Document.ExprScope where

    -- Modules
import Document.Scope
import Document.Phase

import Logic.Expr hiding (Const)

import UnitB.AST 

    -- Libraries
import Control.Applicative
import Control.Lens
import Control.Monad.RWS

import Data.List as L (map)
import Data.Map as M hiding (mapMaybe)
import Data.Maybe as M
import Data.Typeable

import Utilities.HeterogenousEquality
import Utilities.Syntactic
import Utilities.TH
import Utilities.Trace ()

data CoarseSchedule = CoarseSchedule 
        { _coarseScheduleEvtExpr :: Expr
        , _coarseScheduleDeclSource :: DeclSource
        , _coarseScheduleLineInfo :: LineInfo }
    deriving (Eq,Ord,Typeable)
data FineSchedule = FineSchedule 
        { _fineScheduleEvtExpr :: Expr
        , _fineScheduleDeclSource :: DeclSource
        , _fineScheduleLineInfo :: LineInfo }
    deriving (Eq,Ord,Typeable)
data Guard = Guard 
        { _guardEvtExpr :: Expr
        , _guardDeclSource :: DeclSource
        , _guardLineInfo :: LineInfo }
    deriving (Eq,Ord,Typeable)
data Witness = Witness 
        { _witnessVar :: Var
        , _witnessEvtExpr :: Expr 
        , _witnessDeclSource :: DeclSource
        , _witnessLineInfo :: LineInfo }
    deriving (Eq,Ord,Typeable)
data ActionDecl = DelAction 
        { _actionOptEventExpr :: Maybe Action
        , _actionDeclDeclSource :: DeclSource
        , _actionDeclLineInfo :: LineInfo }
    | Action 
        { _actionEventExpr :: Action
        , _actionDeclDeclSource :: DeclSource
        , _actionDeclLineInfo :: LineInfo }
    deriving (Eq,Ord,Typeable)


makeFields ''CoarseSchedule
makeFields ''FineSchedule
makeFields ''Guard
makeFields ''ActionDecl
makeFields ''Witness

instance HasEvtExpr ActionDecl Action where
    evtExpr f (Action x y z) = (\x -> Action x y z) <$> f x
    evtExpr f (DelAction x y z) = (\x -> DelAction (Just x) y z) <$> f (M.fromJust x)

data EvtExprScope = forall a. IsEvtExpr a => EvtExprScope a
    deriving (Typeable)

instance Eq EvtExprScope where
    EvtExprScope x == EvtExprScope y = h_equal x y

instance Ord EvtExprScope where
    compare (EvtExprScope x) (EvtExprScope y) = h_compare x y

instance Show EvtExprScope where
    show (EvtExprScope x) = show x

addToEventTable :: (MonadState MachinePh3 m, Ord l)
                => Lens' EventPh3 (Map l a)
                -> l -> EventId -> a -> m ()
addToEventTable ln lbl eid x = modify $ over (pEvents . at eid . inside . ln) (insert lbl x)
    where
        inside :: Lens' (Maybe a) a
        inside f (Just x) = Just <$> f x
        inside _ Nothing = error "adding elements to a non-existing event"

newtype LensT a b = LensT { getLens :: Lens' a b }

data EvtExprGroup = forall a. IsEvtExpr a => EvtExprGroup [(Maybe EventId,[(Label,a)])]

class ( Eq a, Ord a, Typeable a
      , Show a, Scope a
      , HasLineInfo a LineInfo
      , HasDeclSource a DeclSource ) => IsEvtExpr a where
    parseEvtExpr :: [(Maybe EventId,[(Label,a)])] 
                 -> RWS () [Error] MachinePh3 ()

instance HasDeclSource EvtExprScope DeclSource where
    declSource f (EvtExprScope x) = EvtExprScope <$> declSource f x

instance HasLineInfo EvtExprScope LineInfo where
    lineInfo f (EvtExprScope x) = EvtExprScope <$> lineInfo f x

instance Show CoarseSchedule where
    show (CoarseSchedule _ _ _) = "coarse schedule"
instance Show FineSchedule where
    show (FineSchedule _ _ _) = "fine schedule"
instance Show Witness where
    show (Witness _ _ _ _) = "witness"
instance Show Guard where
    show (Guard _ _ _) = "guard"
instance Show ActionDecl where
    show (Action _ _ _) = "action"
    show (DelAction _ _ _) = "delete action"

data EventExpr = EventExpr (Map (Maybe EventId) EvtExprScope)
    deriving (Eq,Ord,Typeable)
data Invariant = Invariant 
        { _invariantMchExpr :: Expr
        , _invariantDeclSource :: DeclSource
        , _invariantLineInfo :: LineInfo }
    deriving (Eq,Ord,Typeable)
data TransientProp = TransientProp
        { _transientPropMchExpr :: Transient
        , _transientPropDeclSource :: DeclSource
        , _transientPropLineInfo :: LineInfo }
    deriving (Eq,Ord,Typeable)
data ConstraintProp = ConstraintProp
        { _constraintPropMchExpr :: Constraint
        , _constraintPropDeclSource :: DeclSource
        , _constraintPropLineInfo :: LineInfo }
    deriving (Eq,Ord,Typeable)
data SafetyDecl = SafetyProp
        { _safetyDeclMchExpr :: SafetyProp
        , _safetyDeclDeclSource :: DeclSource
        , _safetyDeclLineInfo :: LineInfo }
    deriving (Eq,Ord,Typeable)
data ProgressDecl = ProgressProp
        { _progressDeclMchExpr :: ProgressProp
        , _progressDeclDeclSource :: DeclSource
        , _progressDeclLineInfo :: LineInfo }
    deriving (Eq,Ord,Typeable)
data Initially = DelInit
            { initiallyMMchExpr :: Maybe Expr
            , _initiallyDeclSource :: DeclSource
            , _initiallyLineInfo :: LineInfo }
        | Initially
            { initiallyMchExpr :: Expr
            , _initiallyDeclSource :: DeclSource
            , _initiallyLineInfo :: LineInfo }
    deriving (Eq,Ord,Typeable)
data Axiom = Axiom
        { _axiomMchExpr :: Expr
        , _axiomDeclSource :: DeclSource
        , _axiomLineInfo :: LineInfo }
    deriving (Eq,Ord,Typeable)

makeFields ''Axiom
makeFields ''ProgressDecl
makeFields ''Initially
makeFields ''SafetyDecl
makeFields ''ConstraintProp
makeFields ''TransientProp
makeFields ''Invariant

class ( Scope a, Typeable a ) 
        => IsExprScope a where
    parseExpr :: [(Label, a)] -> RWS () [Error] MachinePh3 ()

data ExprScope = forall t. IsExprScope t => ExprScope t
    deriving Typeable

instance Eq ExprScope where
    ExprScope x == ExprScope y = h_equal x y

instance Ord ExprScope where
    compare (ExprScope x) (ExprScope y) = h_compare x y

data ExprGroup = forall a. IsExprScope a => ExprGroup [(Label,a)]

existential ''EvtExprGroup
existential ''ExprGroup
existential ''ExprScope
existential ''EvtExprScope

parseExprScope :: Map Label ExprScope
               -> MachinePh3
               -> (MachinePh3,[Error])
parseExprScope xs = execRWS (mapM_ g $ groupExprGroup (++) $ L.map f $ M.toList xs) ()
    where
        f (lbl,ExprScope x) = ExprGroup [(lbl,x)]
        g (ExprGroup xs)    = parseExpr xs

instance Scope CoarseSchedule where
    error_item x = (show x, view lineInfo x)

instance Scope FineSchedule where
    error_item x = (show x, view lineInfo x)

instance Scope Guard where
    error_item x = (show x, view lineInfo x)

instance Scope Witness where
    error_item x = (show x, view lineInfo x)

instance Scope ActionDecl where
    keep_from s x@(DelAction _ _ _) = guard (s == Inherited) >> return x
    keep_from s x@(Action _ s' _) = guard (s == s') >> return x
    error_item x = (show x, view lineInfo x)
    clashes x y = f x == f y
        where
            f (DelAction Nothing _ _) = False
            f (DelAction (Just _) _ _) = True
            f (Action _ _ _) = True
    merge_scopes (DelAction Nothing y li) (Action a _ _) = DelAction (Just a) y li
    merge_scopes (Action a _ _) (DelAction Nothing y li) = DelAction (Just a) y li
    merge_scopes _ _ = error "ActionDecl Scope.merge_scopes: Evt, Evt"

instance Scope EvtExprScope where
    keep_from s x = applyEvtExprScope (keep_from s) x
    make_inherited e = applyEvtExprScope make_inherited e
    error_item e = getConst $ applyEvtExprScope (Const . error_item) e
    clashes x y = fromMaybe True $ getConst <$> apply2EvtExprScope (fmap Const <$> clashes) x y
    merge_scopes x y = fromMaybe err $ runIdentity <$> apply2EvtExprScope (fmap Identity <$> merge_scopes) x y
        where
            err = error "EvtExprScope Scope.merge_scopes: _, _"

instance Scope ExprScope where
    keep_from s x = applyExprScope (keep_from s) x
    make_inherited e = applyExprScope make_inherited e
    error_item e = getConst $ applyExprScope (Const . error_item) e
    clashes x y = fromMaybe True $ getConst <$> apply2ExprScope (fmap Const <$> clashes) x y
    merge_scopes x y = fromMaybe err $ runIdentity <$> apply2ExprScope (fmap Identity <$> merge_scopes) x y
        where
            err = error "ExprScope Scope.merge_scopes: _, _"
