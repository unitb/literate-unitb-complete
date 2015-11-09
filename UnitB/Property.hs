module UnitB.Property where

    -- Modules
import Logic.Expr.Scope
import Logic.Proof

import Theories.SetTheory

import UnitB.Expr

    -- Libraries
import Control.DeepSeq
import Control.Lens hiding (Const)

import Data.Default
import Data.Foldable
import Data.Map  as M hiding (fold)
import Data.Semigroup
import Data.List as L
import Data.String
import Data.Typeable

import GHC.Generics

import Text.Printf

import Utilities.Instances
import Utilities.Invariant
import Utilities.TableConstr

type Constraint = Constraint' Expr
type RawConstraint = Constraint' RawExpr

data Constraint' expr = 
        Co [Var] expr
    deriving (Eq,Ord,Show,Functor,Foldable,Traversable,Generic)

type TrHint = TrHint' Expr
type RawTrHint = TrHint' RawExpr

data TrHint' expr = TrHint (Map String (Type,expr)) (Maybe ProgId)
    deriving (Eq,Ord,Show,Functor,Foldable,Traversable,Generic)


empty_hint :: TrHint' expr
empty_hint = TrHint empty Nothing

type Transient = Transient' Expr
type RawTransient = Transient' RawExpr

data Transient' expr = 
        Tr 
            (Map String Var)     -- Free variables
            expr                 -- Predicate
            [EventId]            -- Event, Schedule 
            (TrHint' expr)       -- Hints for instantiation
            -- (Map String Expr)    -- Index substitution
            -- (Maybe Label)        -- Progress Property for fine schedule
    deriving (Eq,Ord,Show,Functor,Foldable,Traversable,Generic)

data Direction = Up | Down
    deriving (Eq,Show,Generic)

newtype EventId = EventId Label
    deriving (Eq,Ord,Typeable,Generic)

instance Show EventId where
    show (EventId x) = show x

instance IsString EventId where
    fromString = EventId . fromString

instance IsLabel EventId where
    as_label (EventId lbl) = lbl

data Variant = 
        SetVariant     Var RawExpr RawExpr Direction
      | IntegerVariant Var RawExpr RawExpr Direction
    deriving (Eq,Show,Generic)

type PropertySet = PropertySet' Expr
type RawPropertySet = PropertySet' RawExpr

data PropertySet' expr = PS
        { _transient    :: Map Label (Transient' expr)
        , _constraint   :: Map Label (Constraint' expr)
        , _inv          :: Map Label expr       -- inv
        , _inv_thm      :: Map Label expr       -- inv thm
        , _progress     :: Map ProgId (ProgressProp' expr)
--        , schedule     :: Map Label Schedule
        , _safety       :: Map Label (SafetyProp' expr)
        }
    deriving (Eq,Functor,Foldable,Traversable,Generic)

newtype ProgId = PId { getProgId :: Label }
    deriving (Eq,Ord,IsString,Typeable,Generic)

instance IsLabel ProgId where
    as_label (PId lbl) = lbl

instance Show ProgId where
    show (PId x) = show x

type ProgressProp = ProgressProp' Expr
type RawProgressProp = ProgressProp' RawExpr

data ProgressProp' expr = LeadsTo [Var] expr expr
    deriving (Eq,Ord,Typeable,Functor,Foldable,Traversable,Generic)

type SafetyProp = SafetyProp' Expr
type RawSafetyProp = SafetyProp' RawExpr

data SafetyProp' expr = Unless [Var] expr expr (Maybe EventId)
    deriving (Eq,Ord,Typeable,Functor,Foldable,Traversable,Generic)

instance Show expr => Show (ProgressProp' expr) where
    show (LeadsTo _ p q) = show p ++ "  |->  " ++ show q

instance Show expr => Show (SafetyProp' expr) where
    show (Unless _ p q ev) = show p ++ "  UNLESS  " ++ show q ++ except
        where
            except = maybe "" (("  EXCEPT  " ++) . show) ev

instance Show expr => Show (PropertySet' expr) where
    show x = printf "PropertySet { %s }" 
        $ intercalate ", " $ L.map (\(x,y) -> x ++ " = " ++ y)
            [ ("transient",  show $ _transient x)
            , ("constraint", show $ _constraint x)
            , ("inv", show $ _inv x)
            , ("inv_thm", show $ _inv_thm x)
            , ("progress", show $ _progress x)
            , ("safety", show $ _safety x)
            ]

makeRecordConstr ''PropertySet'

type PropertySetField = PropertySet'Field Expr

empty_property_set :: PropertySet' expr
empty_property_set = makePropertySet' []

instance Default (PropertySet' expr) where
    def = empty_property_set

hasClashes :: PropertySet' expr -> PropertySet' expr -> PropertySet' expr
hasClashes x y = getIntersection $ Intersection x <> Intersection y

noClashes :: Show expr => PropertySet' expr -> PropertySet' expr -> Invariant ()
noClashes p0 p1 = allTables inv (hasClashes p0 p1) >> return ()
    where
        inv msg m = withPrefix msg $ do
            (show $ keys m) ## M.null m
            return m

instance Semigroup (Intersection (PropertySet' expr)) where
    (<>) = genericSemigroupMAppendWith

variant_equals_dummy :: Variant -> RawExpr
--variant_equals_dummy (SetVariant d var _ _)     = Word d `zeq` asExpr var
variant_equals_dummy (IntegerVariant d var _ _) = Word d `zeq` asExpr var
variant_equals_dummy (SetVariant d var _ _) = Word d `zeq` asExpr var

variant_decreased :: Variant -> RawExpr
variant_decreased (SetVariant d var _ Up)       = ($typeCheck) $ Right (Word d) `zsubset` Right (asExpr var)
variant_decreased (IntegerVariant d var _ Up)   = Word d `zless` asExpr var
variant_decreased (SetVariant d var _ Down)     = ($typeCheck) $ Right (asExpr var) `zsubset` Right (Word d)
variant_decreased (IntegerVariant d var _ Down) = asExpr var `zless` Word d

variant_bounded :: Variant -> RawExpr
--variant_bounded (SetVariant d var _ _)     = error "set variants unavailable"
variant_bounded (IntegerVariant _ var b Down) = asExpr b `zle` asExpr var
variant_bounded (IntegerVariant _ var b Up)   = asExpr var `zle` asExpr b
variant_bounded (SetVariant _ var b Down) = ($typeCheck) $ 
    mzand (Right (asExpr b) `zsubset` Right (asExpr var))
          (mzfinite $ Right (asExpr var) `zsetdiff` Right (asExpr b))
variant_bounded (SetVariant _ var b Up)   = ($typeCheck) $ 
    mzand (Right (asExpr var) `zsubset` Right (asExpr b))
          (mzfinite $ Right (asExpr b) `zsetdiff` Right (asExpr var))

make_unique :: String           -- suffix to be added to the name of variables
            -> Map String Var   -- set of variables that must renamed
            -> RawExpr          -- expression to rewrite
            -> RawExpr
make_unique suf vs w@(Word (Var vn vt)) 
        | vn `M.member` vs    = Word (Var (vn ++ suf) vt)
        | otherwise           = w
make_unique _ _ c@(Const _ _)    = c
make_unique suf vs (FunApp f xs)     = FunApp f $ L.map (make_unique suf vs) xs
make_unique suf vs (Cast e t)        = Cast (make_unique suf vs e) t
make_unique suf vs (Lift e t)        = Lift (make_unique suf vs e) t
make_unique suf vs (Binder q d r xp t) = Binder q d (f r) (f xp) t
    where
        local = (L.foldr M.delete vs (L.map (view name) d))
        f = make_unique suf local

makeLenses ''PropertySet'

instance HasScope expr => HasScope (Transient' expr) where
    scopeCorrect' (Tr vs e _ _) = withVars vs $ scopeCorrect' e

instance HasScope expr => HasScope (ProgressProp' expr) where
    scopeCorrect' (LeadsTo vs p q) = withVars vs $ scopeCorrect' p <> scopeCorrect' q

instance HasScope expr => HasScope (SafetyProp' expr) where
    scopeCorrect' (Unless vs p q _) = withVars vs $ scopeCorrect' p <> scopeCorrect' q

instance HasScope expr => HasScope (Constraint' expr) where
    scopeCorrect' (Co vs e) = withPrimes $ withVars (symbol_table vs) $ scopeCorrect' e

instance HasScope expr => HasScope (PropertySet' expr) where
    scopeCorrect' x = withPrefix "props" $ fold $
        [ withPrefix "transient"  $ foldMapWithKey scopeCorrect'' (x^.transient)
        , withPrefix "constraint" $ foldMapWithKey scopeCorrect'' (x^.constraint)
        , withPrefix "invariant"  $ foldMapWithKey scopeCorrect'' (x^.inv)
        , withPrefix "theorem"    $ foldMapWithKey scopeCorrect'' (x^.inv_thm)
        , withPrefix "progress"   $ foldMapWithKey scopeCorrect'' (x^.progress)
        , withPrefix "safety" $ foldMapWithKey scopeCorrect'' (x^.safety)
        --, withPrefix "proofs" $ foldMapWithKey scopeCorrect'' (x^.proofs)
        ]

instance Monoid (PropertySet' expr) where
    mempty = genericMEmpty
    mappend = genericMAppend

instance NFData ProgId
instance NFData expr => NFData (Constraint' expr)
instance NFData Direction
instance NFData expr => NFData (ProgressProp' expr)
instance NFData expr => NFData (PropertySet' expr)
instance NFData expr => NFData (SafetyProp' expr)
instance NFData expr => NFData (Transient' expr)
instance NFData expr => NFData (TrHint' expr)
instance NFData Variant
instance NFData EventId
