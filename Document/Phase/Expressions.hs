{-# LANGUAGE TypeOperators
    , Arrows
    , RankNTypes 
    , TypeFamilies
    , ViewPatterns
    , TupleSections
    , DeriveFunctor
    , FlexibleContexts
    #-}
module Document.Phase.Expressions where

    --
    -- Modules
    --
import Document.ExprScope as ES
import Document.Pipeline
import Document.Phase as P
import Document.Phase.Transient
import Document.Proof
import Document.Scope
import Document.Visitor

import Latex.Parser hiding (contents)

import UnitB.AST as AST
import UnitB.Expr

import Theories.SetTheory

    --
    -- Libraries
    --
import Control.Arrow hiding (left,app) -- (Arrow,arr,(>>>))
import qualified Control.Category as C
import           Control.Applicative 

import           Control.Monad 
import           Control.Monad.Reader.Class 
import           Control.Monad.Reader (Reader)
import           Control.Monad.State.Class 
import           Control.Monad.Writer.Class 
import           Control.Monad.Trans
import           Control.Monad.Trans.Either
import           Control.Monad.Trans.RWS as RWS ( RWS )
import qualified Control.Monad.Writer as W

import Control.Lens as L hiding ((|>),(<.>),(<|),indices,Context)

import           Data.Either hiding (isLeft,isRight)
import           Data.Either.Combinators
import           Data.Functor.Compose
import           Data.Map   as M hiding ( map, foldl, (\\) )
import qualified Data.Map   as M
import qualified Data.Maybe as MM
import           Data.List as L hiding ( union, insert, inits )
import qualified Data.List.NonEmpty as NE
import qualified Data.Set as S
import qualified Data.Traversable as T

import Utilities.Format
import Utilities.Syntactic

withHierarchy :: Pipeline MM (Hierarchy MachineId,MTable a) (MTable b)
              -> Pipeline MM (SystemP a) (SystemP b)
withHierarchy cmd = proc (SystemP ref tab) -> do
    tab' <- cmd -< (ref,tab)
    returnA -< SystemP ref tab'

run_phase3_exprs :: Pipeline MM SystemP2 SystemP3
run_phase3_exprs = -- withHierarchy $ _ *** expressions >>> _ -- (C.id &&& expressions) >>> _ -- liftP (uncurry wrapup)
        proc (SystemP ref tab) -> do
            es <- C.id &&& expressions -< tab
            x  <- liftP (uncurry wrapup) -< (ref,es)
            returnA -< SystemP ref x
    where
        err_msg :: Label -> String
        err_msg = format "Multiple expressions with the label {0}"
        wrapup r_ord (p2,es) = do
            let -- names = M.map (view pEventRenaming) p2
                es' = inherit2 p2 r_ord . unionsWith (++) <$> es
            exprs <- triggerM
                =<< make_all_tables' err_msg
                =<< triggerM es'
            xs <- T.sequence $ make_phase3 <$> p2 <.> exprs
            --store <- triggerM store
            return xs
        expressions = run_phase 
            [ assignment
            , bcmeq_assgn
            , bcmsuch_assgn
            , bcmin_assgn
            , guard_decl
            , guard_removal
            , coarse_removal
            , fine_removal
            , default_schedule_decl
            , fine_sch_decl
            , coarse_sch_decl
            , initialization
            , assumption
            , invariant
            , mch_theorem
            , transient_prop
            , transientB_prop
            , constraint_prop
            , progress_prop
            , safetyA_prop
            , safetyB_prop
            , remove_assgn
            , remove_init
            , init_witness_decl
            , witness_decl ]

make_phase3 :: MachineP2 -> Map Label ExprScope -> MM' c MachineP3
make_phase3 p2 exprs' = do
        join $ upgradeM
            newThy newMch
            <$> liftEvent toOldEvtExpr
            <*> liftEvent2 toNewEvtExpr toNewEvtExprDefault
            <*> pure p2
    where
        exprs = M.toList exprs'
        liftEvent2 :: (   Label 
                      -> ExprScope 
                      -> Reader MachineP2
                                [Either Error (EventId, [EventP3Field])])
                   -> (   Label 
                      -> ExprScope 
                      -> Reader MachineP2
                                [Either Error (EventId, [EventP3Field])])
                   -> MM' c (MachineP2
                        -> SkipOrEvent -> EventP2 -> MM' c EventP3)
        liftEvent2 f g = do
            m <- fromListWith (++).L.map (first Right) <$> liftFieldM f p2 exprs
            m' <- fromListWith (++).L.map (first Right) <$> liftFieldM g p2 exprs
            let ms = M.unionWith (++) m' m
            return $ \_ eid e -> return $ makeEventP3 e (findWithDefault [] eid ms)
        liftEvent :: (   Label 
                      -> ExprScope 
                      -> Reader MachineP2
                                [Either Error (EventId, [EventP3Field])])
                  -> MM' c (
                        MachineP2
                        -> SkipOrEvent -> EventP2 -> MM' c EventP3)
        liftEvent f = liftEvent2 f (\_ _ -> return [])
        newMch :: MachineP2
               -> MM' c (MachineP3' EventP2 TheoryP2)
        newMch m = makeMachineP3' m 
                <$> (makePropertySet' <$> liftFieldM toOldPropSet m exprs)
                <*> (makePropertySet' <$> liftFieldM toNewPropSet m exprs)
                <*> liftFieldM toMchExpr m exprs
        newThy t = makeTheoryP3 t <$> liftFieldM toThyExpr t exprs

assignment :: MPipeline MachineP2
                    [(Label,ExprScope)]
assignment = machineCmd "\\evassignment" $ \(ev_lbl, lbl, xs) _m p2 -> do
            ev <- get_event p2 ev_lbl
            pred <- parse_expr''
                (event_parser p2 ev & is_step .~ True) 
                xs
            let frame = M.elems $ (p2^.pStateVars) `M.difference` (p2^.pAbstractVars)
                act = BcmSuchThat frame pred
            li <- lift ask
            return [(lbl,evtScope ev (Action (InhAdd (ev NE.:| [],act)) Local li))]

bcmeq_assgn :: MPipeline MachineP2
                    [(Label,ExprScope)]
bcmeq_assgn = machineCmd "\\evbcmeq" $ \(ev_lbl, lbl, String v, xs) _m p2 -> do
            let _ = lbl :: Label
            ev <- get_event p2 ev_lbl
            var@(Var _ t) <- bind
                (format "variable '{0}' undeclared" v)
                $ v `M.lookup` (p2^.pStateVars)
            li <- lift ask
            xp <- parse_expr''
                (event_parser p2 ev & expected_type .~ Just t)
                xs
            check_types
                $ Right (Word var :: RawExpr) `mzeq` Right (asExpr xp)
            let act = Assign var xp
            return [(lbl,evtScope ev (Action (InhAdd (ev NE.:| [],act)) Local li))]

bcmsuch_assgn :: MPipeline MachineP2
                    [(Label,ExprScope)]
bcmsuch_assgn = machineCmd "\\evbcmsuch" $ \(evt, lbl, vs, xs) _m p2 -> do
            ev <- get_event p2 evt
            li <- lift ask
            xp <- parse_expr''
                    (event_parser p2 ev & is_step .~ True)
                    xs
            vars <- bind_all (map toString vs)
                (format "variable '{0}' undeclared")
                $ (`M.lookup` (p2^.pStateVars))
            let act = BcmSuchThat vars xp
            return [(lbl,evtScope ev (Action (InhAdd (ev NE.:| [],act)) Local li))]

bcmin_assgn :: MPipeline MachineP2
                    [(Label,ExprScope)]
bcmin_assgn = machineCmd "\\evbcmin" $ \(evt, lbl, String v, xs) _m p2 -> do
            ev <- get_event p2 evt
            var@(Var _ t) <- bind
                (format "variable '{0}' undeclared" v)
                $ v `M.lookup` (p2^.pStateVars)
            li  <- lift ask
            xp <- parse_expr''
                    (event_parser p2 ev & expected_type .~ Just (set_type t) )
                    xs
            let act = BcmIn var xp
            check_types $ Right (Word var) `zelem` Right (asExpr xp)
            return [(lbl,evtScope ev (Action (InhAdd (ev NE.:| [],act)) Local li))]

instance Scope Initially where
    type Impl Initially = WithDelete Initially
    kind x = case x^.inhStatus of 
            InhAdd _ -> "initialization"
            InhDelete _ -> "deleted initialization"
    rename_events _ x = [x]

used_var' :: Expr -> Map String Var
used_var' = symbol_table . S.toList . used_var . getExpr

instance IsExprScope Initially where
    toNewEvtExprDefault _ _ = return []
    toMchExpr lbl i  = do
        vs <- view pDelVars
        return $ case (i^.inhStatus,i^.declSource) of
            (InhAdd x,_)
                | L.null lis' -> [Right $ PInit lbl x]
                | otherwise   -> [Left $ MLError msg $ (format "predicate {0}" lbl,li):lis']
                where
                    lis = L.map (first name) $ M.elems $ vs `M.intersection` used_var' x
                    lis' = L.map (first (format "deleted variable {0}")) lis
                    msg  = format "initialization predicate '{0}' refers to deleted variables" lbl
            (InhDelete (Just x),Local) -> [Right $ PDelInits lbl x]
            (InhDelete (Just _),Inherited) -> []
            (InhDelete Nothing,_) -> [Left $ Error msg li]
                where
                    msg = format "initialization predicate '{0}' was deleted but does not exist" lbl
        where
            li = i^.lineInfo
    toThyExpr _ _  = return []
    toNewPropSet _ _ = return []
    toOldPropSet _ _ = return []
    toNewEvtExpr _ _ = return []
    toOldEvtExpr _ _ = return []
    -- parseExpr xs = do
    --     xs <- forM xs $ \(lbl,x) -> do
    --         case x of
    --             Initially (InhAdd x) _ li _ -> do
    --                 vs <- gets $ view pDelVars
    --                 let msg = format "initialization predicate '{0}' refers to deleted variables" lbl
    --                     lis = L.map (first name) $ M.elems $ vs `M.intersection` used_var' x
    --                     lis' = L.map (first (format "deleted variable {0}")) lis
    --                 unless (L.null lis')
    --                     $ tell [MLError msg $ (format "predicate {0}" lbl,li):lis']
    --                 return ([(lbl,x)],[],[])
    --             Initially (InhDelete (Just x)) Local _ _ -> 
    --                 return ([],[(lbl,x)],[(v,x) | v <- S.elems $ used_var x ])
    --             Initially (InhDelete (Just _)) Inherited _ _ -> 
    --                 return ([],[],[])
    --             Initially (InhDelete Nothing) _ li _ -> do
    --                 let msg = format "initialization predicate '{0}' was deleted but does not exist" lbl
    --                 tell [Error msg li]
    --                 return ([],[],[])
    --     let (ys,zs,ws) = mconcat xs 
    --     pInit     %= M.union (M.fromList ys)
    --     pDelInits %= M.union (M.fromList zs)
    --     pInitWitness %= flip M.union (M.fromList ws)

remove_init :: MPipeline MachineP2 [(Label,ExprScope)]
remove_init = machineCmd "\\removeinit" $ \(One lbls) _m _p2 -> do
            li <- lift ask
            return [(lbl,ExprScope $ Initially (InhDelete Nothing) Local li) | lbl <- lbls ]

remove_assgn :: MPipeline MachineP2 [(Label,ExprScope)]
remove_assgn = machineCmd "\\removeact" $ \(evt, lbls) _m p2 -> do
            ev <- get_event p2 evt
            li <- lift ask
            return [(lbl,evtScope ev (Action (InhDelete Nothing) Local li)) | lbl <- lbls ]

witness_decl :: MPipeline MachineP2 [(Label,ExprScope)]
witness_decl = machineCmd "\\witness" $ \(evt, String var, xp) _m p2 -> do
            ev <- get_event p2 evt
            li <- lift ask
            p  <- parse_expr'' (event_parser p2 ev & is_step .~ True) xp
            v  <- bind (format "'{0}' is not a disappearing variable" var)
                (var `M.lookup` (L.view pAbstractVars p2 `M.difference` L.view pStateVars p2))
            return [(label var,evtScope ev (Witness v p Local li))]

instance Scope EventExpr where
    kind (EventExpr m) = show $ kind <$> m
    keep_from s (EventExpr m) = Just $ EventExpr $ M.mapMaybe (keep_from s) m
    make_inherited (EventExpr m) = Just $ EventExpr (M.map f m)
        where
            f x = set declSource Inherited x
    clashes (EventExpr m0) (EventExpr m1) = not $ M.null 
            $ M.filter id
            $ M.intersectionWith clashes m0 m1
    error_item (EventExpr m) = head' $ elems $ mapWithKey msg m
        where
            head' [x] = x
            head' _ = error "Scope ExprScope: head'"
            msg (Right k) sc 
                | inheritedFrom sc `elem` [[],[k]]
                    = (format "{1} (event {0})" k (kind sc) :: String, view lineInfo sc)
                | otherwise
                    = (format "{1} (event {0}, from {2})" k (kind sc) parents :: String, view lineInfo sc)
                where
                    parents = intercalate "," $ map show $ inheritedFrom sc
            msg (Left _) sc = (format "{0} (initialization)" sc :: String, view lineInfo sc)
    merge_scopes (EventExpr m0) (EventExpr m1) = EventExpr $ unionWith merge_scopes m0 m1
    rename_events m (EventExpr es) = map EventExpr $ concatMap f $ toList es
        where
            lookup x = MM.fromMaybe [x] $ M.lookup x m
            f (Right eid,x) = [ singleton (Right e) $ setSource eid x | e <- lookup eid ]
            f (Left InitEvent,x) = [singleton (Left InitEvent) x]

checkLocalExpr :: ( HasInhStatus decl (InhStatus expr)
                  , HasLineInfo decl LineInfo )
               => String -> (expr -> Map String Var)
               -> [(Maybe EventId, [(Label,decl)])] 
               -> RWS () [Error] MachineP3 ()
checkLocalExpr expKind free xs = do
        vs <- use pDelVars
        let xs' = [ (eid,lbl,sch) | (e,ss) <- xs, (lbl,sch) <- ss, eid <- MM.maybeToList e ]
        forM_ xs' $ \(eid,lbl,sch) -> do
            case (sch ^. inhStatus) of
                InhAdd expr -> do
                    let msg = format "event '{1}', {2} '{0}' refers to deleted variables" lbl eid expKind
                        errs   = vs `M.intersection` free expr
                        schLI  = (format "{1} '{0}'" lbl expKind, sch ^. lineInfo)
                        varsLI = L.map (first $ format "deleted variable '{0}'" . name) (M.elems errs)
                    unless (M.null errs) 
                        $ tell [MLError msg $ schLI : varsLI]
                InhDelete Nothing -> do
                    let msg = format "event '{1}', {2} '{0}' was deleted but does not exist" lbl eid expKind
                        li  = sch ^. lineInfo
                    tell [Error msg li]
                _ -> return ()

checkLocalExpr' :: ( HasInhStatus decl (InhStatus expr)
                  , HasLineInfo decl LineInfo )
               => String -> (expr -> Map String Var)
               -> EventId -> Label -> decl
               -> Reader MachineP2 [Either Error a]
checkLocalExpr' expKind free eid lbl sch = do
            vs <- view pDelVars 
            return $ case (sch ^. inhStatus) of
                InhAdd expr -> 
                    let msg = format "event '{1}', {2} '{0}' refers to deleted variables" lbl eid expKind
                        errs   = vs `M.intersection` free expr
                        schLI  = (format "{1} '{0}'" lbl expKind, sch ^. lineInfo)
                        varsLI = L.map (first $ format "deleted variable '{0}'" . name) (M.elems errs)
                    in if M.null errs then []
                       else [Left $ MLError msg $ schLI : varsLI]
                InhDelete Nothing -> 
                    let msg = format "event '{1}', {2} '{0}' was deleted but does not exist" lbl eid expKind
                        li  = sch ^. lineInfo
                    in [Left $ Error msg li]
                _ -> []
        -- xs' = [ (eid,lbl,sch) | (e,ss) <- xs, (lbl,sch) <- ss, eid <- MM.maybeToList e ]

parseEvtExpr :: ( HasInhStatus decl (EventInhStatus Expr)
                , HasLineInfo decl LineInfo
                , HasDeclSource decl DeclSource)
             => String 
             -> (Label -> Expr -> field)
             -> RefScope
             -> EventId -> Label -> decl
             -> Reader MachineP2 [Either Error (EventId,[field])]
parseEvtExpr expKind = parseEvtExpr' expKind used_var'


parseEvtExpr' :: ( HasInhStatus decl (EventInhStatus expr)
                 , HasLineInfo decl LineInfo
                 -- , HasMchExpr decl expr
                 , HasDeclSource decl DeclSource)
              => String 
              -> (expr -> Map String Var)
              -> (Label -> expr -> field)
              -> RefScope
              -> EventId -> Label -> decl
              -> Reader MachineP2 [Either Error (EventId,[field])]
parseEvtExpr' expKind fvars field scope evt lbl decl = 
    (++) <$> check
         <*>
        -- (old_xs, del_xs, new_xs)
        case (decl^.inhStatus, decl^.declSource) of
            (InhAdd e, Inherited) -> return $ old e ++ new e 
                                       -- ([(k,[x])],[],[(k,[x])])
            (InhAdd e, Local)     -> return $ new e
                                       -- ([],[],[(k,[x])])
            (InhDelete _, Inherited) -> return [] -- ([],[],[])
            (InhDelete (Just e), Local) -> return $ old e
            (InhDelete Nothing, Local)  -> return [] 
    where
        check = case scope of
                    Old -> return []
                    New -> checkLocalExpr' expKind (fvars.snd) evt lbl decl
        old = case scope of
            Old -> \(evts,e) -> [Right (ev,[field lbl e]) | ev <- NE.toList evts]
            New -> const []
        new = case scope of
            Old -> const []
            New -> \(_,e) -> [Right (evt,[field lbl e])]

instance IsEvtExpr CoarseSchedule where
    toMchScopeExpr _ _  = return []
    defaultEvtWitness _ _ = return []
    toEvtScopeExpr = parseEvtExpr "coarse schedule" ECoarseSched
--     parseEvtExpr xs = do
--         parseEvtExprChoice' pOldCoarseSched pDelCoarseSched pNewCoarseSched fst xs
--         checkLocalExpr "coarse schedule" used_var' xs

instance IsEvtExpr FineSchedule where
    toMchScopeExpr _ _  = return []
    defaultEvtWitness _ _ = return []
    toEvtScopeExpr = parseEvtExpr "fine schedule" EFineSched
--     parseEvtExpr xs = do
--         parseEvtExprChoice' pOldFineSched pDelFineSched pNewFineSched fst xs
--         checkLocalExpr "fine schedule" used_var' xs

instance IsEvtExpr Guard where
    toMchScopeExpr _ _  = return []
    defaultEvtWitness _ _ = return []
    toEvtScopeExpr = parseEvtExpr "guard" EGuards
--     parseEvtExpr xs = do
--         parseEvtExprChoice' pOldGuards pDelGuards pNewGuards fst xs
--         checkLocalExpr "guard" used_var' xs

guard_decl :: MPipeline MachineP2
                    [(Label,ExprScope)]
guard_decl = machineCmd "\\evguard" $ \(evt, lbl, xs) _m p2 -> do
            ev <- get_event p2 evt
            li <- lift ask
            xp <- parse_expr'' (event_parser p2 ev) xs
            return [(lbl,evtScope ev (Guard (InhAdd (ev NE.:| [],xp)) Local li))]

guard_removal :: MPipeline MachineP2 [(Label,ExprScope)]
guard_removal = machineCmd "\\removeguard" $ \(evt_lbl,lbls) _m p2 -> do
        ev  <- get_event p2 evt_lbl
        li <- lift ask
        return [(lbl,evtScope ev (Guard (InhDelete Nothing) Local li)) | lbl <- lbls ]

coarse_removal :: MPipeline MachineP2 [(Label,ExprScope)]
coarse_removal = machineCmd "\\removecoarse" $ \(evt_lbl,lbls) _m p2 -> do
        ev  <- get_event p2 evt_lbl
        li <- lift ask
        return [(lbl,evtScope ev (CoarseSchedule (InhDelete Nothing) Local li)) | lbl <- lbls ]

fine_removal :: MPipeline MachineP2 [(Label,ExprScope)]
fine_removal = machineCmd "\\removefine" $ \(evt_lbl,lbls) _m p2 -> do
        ev  <- get_event p2 evt_lbl
        li <- lift ask
        return [(lbl,evtScope ev (FineSchedule (InhDelete Nothing) Local li)) | lbl <- lbls ]

coarse_sch_decl :: MPipeline MachineP2
                    [(Label,ExprScope)]
coarse_sch_decl = machineCmd "\\cschedule" $ \(evt, lbl, xs) _m p2 -> do
            ev <- get_event p2 evt
            li <- lift ask
            xp <- parse_expr'' (schedule_parser p2 ev) xs
            return [(lbl,evtScope ev (CoarseSchedule (InhAdd (ev NE.:| [],xp)) Local li))]

fine_sch_decl :: MPipeline MachineP2
                    [(Label,ExprScope)]
fine_sch_decl = machineCmd "\\fschedule" $ \(evt, lbl, xs) _m p2 -> do
            ev <- get_event p2 evt
            li <- lift ask
            xp <- parse_expr'' (schedule_parser p2 ev) xs
            return [(lbl,evtScope ev (FineSchedule (InhAdd (ev NE.:| [],xp)) Local li))]

        -------------------------
        --  Theory Properties  --
        -------------------------

instance Scope Axiom where
    kind _ = "axiom"
    merge_scopes _ _ = error "Axiom Scope.merge_scopes: _, _"
    clashes _ _ = True
    keep_from s x = guard (s == view declSource x) >> return x
    rename_events _ x = [x]

parseExpr' :: (HasMchExpr b a, Ord label)
           => Lens' MachineP3 (Map label a) 
           -> [(label,b)] 
           -> RWS () [Error] MachineP3 ()
parseExpr' ln xs = modify $ ln %~ M.union (M.fromList $ map (second $ view mchExpr) xs)

instance IsExprScope Axiom where
    toNewEvtExprDefault _ _ = return []
    toMchExpr _ _    = return []
    toThyExpr lbl x  = return [Right $ PAssumptions lbl $ x^.mchExpr]
    toNewPropSet _ _ = return []
    toOldPropSet _ _ = return []
    toNewEvtExpr _ _ = return []
    toOldEvtExpr _ _ = return []
    -- parseExpr = parseExpr' pAssumptions

assumption :: MPipeline MachineP2
                    [(Label,ExprScope)]
assumption = machineCmd "\\assumption" $ \(lbl,xs) _m p2 -> do
            li <- lift ask
            xp <- parse_expr'' (p2^.pCtxSynt) xs
            return [(lbl,ExprScope $ Axiom xp Local li)]

        --------------------------
        --  Program properties  --
        --------------------------

initialization :: MPipeline MachineP2
                    [(Label,ExprScope)]
initialization = machineCmd "\\initialization" $ \(lbl,xs) _m p2 -> do
            li <- lift ask
            xp <- parse_expr'' (p2^.pMchSynt) xs
            return [(lbl,ExprScope $ Initially (InhAdd xp) Local li)]

default_schedule_decl :: MPipeline MachineP2 [(Label,ExprScope)]
default_schedule_decl = arr $ \p2 -> 
        Just $ M.map (map default_sch.elems . M.mapWithKey const.view pNewEvents) p2
    where
        li = LI "default" 1 1
        default_sch e = ( label "default",
                          ExprScope $ EventExpr 
                            $ singleton (Right e) (EvtExprScope $ CoarseSchedule (InhAdd (e NE.:| [],zfalse)) Inherited li))


instance Scope Invariant where
    kind _ = "invariant"
    rename_events _ x = [x]

instance IsExprScope Invariant where
    toNewEvtExprDefault _ _ = return []
    toMchExpr lbl e = return [Right $ PInvariant lbl $ e^.mchExpr]
    toThyExpr _ _   = return []
    toNewPropSet lbl x = return $ if x^.declSource == Local 
            then [Right $ Inv lbl $ x^.mchExpr] 
            else []
    toOldPropSet lbl x = return $ if x^.declSource == Inherited 
            then [Right $ Inv lbl $ x^.mchExpr] 
            else []
    toNewEvtExpr _ _ = return []
    toOldEvtExpr _ _ = return []
    -- parseExpr xs = do
    --     parseExpr' pInvariant xs
    --     modifyProps inv xs

invariant :: MPipeline MachineP2
                    [(Label,ExprScope)]
invariant = machineCmd "\\invariant" $ \(lbl,xs) _m p2 -> do
            li <- lift ask
            xp <- parse_expr'' (p2^.pMchSynt) xs
            return [(lbl,ExprScope $ Invariant xp Local li)]

instance Scope InvTheorem where
    kind _ = "theorem"
    rename_events _ x = [x]

instance IsExprScope InvTheorem where
    toNewEvtExprDefault _ _ = return []
    toMchExpr lbl e = return [Right $ PInvariant lbl $ e^.mchExpr]
    toThyExpr _ _   = return []
    toNewPropSet lbl x = return $ if x^.declSource == Local 
            then [Right $ Inv_thm lbl $ x^.mchExpr] 
            else []
    toOldPropSet lbl x = return $ if x^.declSource == Inherited 
            then [Right $ Inv_thm lbl $ x^.mchExpr] 
            else []
    toNewEvtExpr _ _ = return []
    toOldEvtExpr _ _ = return []
    -- parseExpr xs = do
    --     parseExpr' pInvariant xs
    --     modifyProps inv_thm xs

mch_theorem :: MPipeline MachineP2
                    [(Label,ExprScope)]
mch_theorem = machineCmd "\\theorem" $ \(lbl,xs) _m p2 -> do
            li <- lift ask
            xp <- parse_expr'' (p2^.pMchSynt) xs
            return [(lbl,ExprScope $ InvTheorem xp Local li)]

instance Scope TransientProp where
    kind _ = "transient predicate"
    rename_events _ x = [x]
instance IsExprScope TransientProp where
    toNewEvtExprDefault _ _ = return []
    toMchExpr lbl e = return [Right $ PTransient lbl $ e^.mchExpr]
    toThyExpr _ _   = return []
    toNewPropSet lbl x = return $ if x^.declSource == Local 
            then [Right $ Transient lbl $ x^.mchExpr] 
            else []
    toOldPropSet lbl x = return $ if x^.declSource == Inherited 
            then [Right $ Transient lbl $ x^.mchExpr] 
            else []
    toNewEvtExpr _ _ = return []
    toOldEvtExpr _ _ = return []
    -- parseExpr xs = do
    --     parseExpr' pTransient xs
    --     modifyProps transient xs

transient_prop :: MPipeline MachineP2
                    [(Label,ExprScope)]
transient_prop = machineCmd "\\transient" $ \(evts, lbl, xs) _m p2 -> do
            _evs <- get_events p2 evts
            li   <- lift ask
            tr   <- parse_expr''
                    (p2^.pMchSynt & free_dummies .~ True) 
                    xs
            let withInd = L.filter (not . M.null . (^. eIndices) . ((p2 ^. pEvents) !)) _evs
            toEither $ error_list 
                [ ( not $ L.null withInd
                  , format "event(s) {0} have indices and require witnesses" 
                        $ intercalate "," $ map show withInd) ]
            let vs = used_var' tr
                fv = vs `M.intersection` (p2^.pDummyVars)
                prop = Tr fv tr evts empty_hint
            return [(lbl,ExprScope $ TransientProp prop Local li)]

transientB_prop :: MPipeline MachineP2
                    [(Label,ExprScope)]
transientB_prop = machineCmd "\\transientB" $ \(evts, lbl, hint, xs) m p2 -> do
            _evs <- get_events p2 evts
            li   <- lift ask
            tr   <- parse_expr''
                    (p2^.pMchSynt & free_dummies .~ True) 
                    xs
            let fv = free_vars' ds tr
                ds = p2^.pDummyVars
            evts' <- bind "Expecting non-empty list of events"
                    $ NE.nonEmpty evts
            hint  <- tr_hint p2 m fv evts' hint
            let prop = Tr fv tr evts hint
            return [(lbl,ExprScope $ TransientProp prop Local li)]

instance IsExprScope ConstraintProp where
    toNewEvtExprDefault _ _ = return []
    toMchExpr _ _ = return []
    toThyExpr _ _ = return []
    toNewPropSet lbl x = return $ if x^.declSource == Local 
            then [Right $ Constraint lbl $ x^.mchExpr] 
            else []
    toOldPropSet lbl x = return $ if x^.declSource == Inherited 
            then [Right $ Constraint lbl $ x^.mchExpr] 
            else []
    toNewEvtExpr _ _ = return []
    toOldEvtExpr _ _ = return []
    -- parseExpr xs = do
    --     modifyProps constraint xs

instance Scope ConstraintProp where
    kind _ = "co property"
    rename_events _ x = [x]

constraint_prop :: MPipeline MachineP2
                    [(Label,ExprScope)]
constraint_prop = machineCmd "\\constraint" $ \(lbl,xs) _m p2 -> do
            li  <- lift ask
            pre <- parse_expr''
                    (p2^.pMchSynt
                        & free_dummies .~ True
                        & is_step .~ True)
                    xs
            let vars = elems $ free_vars' ds pre
                ds = p2^.pDummyVars
                prop = Co vars pre
            return [(lbl,ExprScope $ ConstraintProp prop Local li)]

instance IsExprScope SafetyDecl where
    toNewEvtExprDefault _ _ = return []
    toMchExpr lbl e = return [Right $ PSafety lbl $ e^.mchExpr]
    toThyExpr _ _    = return []
    toNewPropSet lbl x = return $ if x^.declSource == Local 
            then [Right $ Safety lbl $ x^.mchExpr] 
            else []
    toOldPropSet lbl x = return $ if x^.declSource == Inherited 
            then [Right $ Safety lbl $ x^.mchExpr] 
            else []
    toNewEvtExpr _ _ = return []
    toOldEvtExpr _ _ = return []
    -- parseExpr xs = do
    --     parseExpr' pSafety xs
    --     modifyProps safety xs

instance Scope SafetyDecl where
    kind _ = "safety property"
    rename_events _ x = [x]

safety_prop :: Label -> Maybe Label
            -> LatexDoc
            -> LatexDoc
            -> MachineId
            -> MachineP2
            -> M [(Label,ExprScope)]
safety_prop lbl evt pCt qCt _m p2 = do
            li <- lift ask
            p <- unfail $ parse_expr''
                    (p2^.pMchSynt & free_dummies .~ True) 
                    pCt
            q <- unfail $ parse_expr''
                    (p2^.pMchSynt & free_dummies .~ True) 
                    qCt
            maybe (return ()) (void . get_event p2) evt
            p <- trigger p
            q <- trigger q
            let ds  = p2^.pDummyVars
                dum = free_vars' ds p `union` free_vars' ds q
                new_prop = Unless (M.elems dum) p q evt
            return [(lbl,ExprScope $ SafetyProp new_prop Local li)]

safetyA_prop :: MPipeline MachineP2
                    [(Label,ExprScope)]
safetyA_prop = machineCmd "\\safety" 
                $ \(lbl, pCt, qCt) -> safety_prop lbl Nothing pCt qCt

safetyB_prop :: MPipeline MachineP2
                    [(Label,ExprScope)]
safetyB_prop = machineCmd "\\safetyB" 
                $ \(lbl, evt, pCt, qCt) -> safety_prop lbl evt pCt qCt

instance IsExprScope ProgressDecl where
    toNewEvtExprDefault _ _ = return []
    toMchExpr lbl e = return [Right $ PProgress (PId lbl) $ e^.mchExpr]
    toThyExpr _ _   = return []
    toNewPropSet lbl x = return $ if x^.declSource == Local 
            then [Right $ Progress lbl $ x^.mchExpr] 
            else []
    toOldPropSet lbl x = return $ if x^.declSource == Inherited 
            then [Right $ Progress lbl $ x^.mchExpr] 
            else []
    toNewEvtExpr _ _ = return []
    toOldEvtExpr _ _ = return []
    -- parseExpr xs = do
    --     parseExpr' pProgress $ map (first PId) xs
    --     modifyProps progress xs

instance Scope ProgressDecl where
    kind _ = "progress property"
    rename_events _ x = [x]

progress_prop :: MPipeline MachineP2
                    [(Label,ExprScope)]
progress_prop = machineCmd "\\progress" $ \(lbl, pCt, qCt) _m p2 -> do
            li <- lift ask
            p    <- unfail $ parse_expr''
                    (p2^.pMchSynt & free_dummies .~ True)
                    pCt
            q    <- unfail $ parse_expr''
                    (p2^.pMchSynt & free_dummies .~ True)
                    qCt
            p  <- trigger p
            q  <- trigger q
            let ds  = p2^.pDummyVars
                dum = free_vars' ds p `union` free_vars' ds q
                new_prop = LeadsTo (M.elems dum) p q
--             new_deriv <- bind (format "proof step '{0}' already exists" lbl)
--                 $ insert_new lbl (Rule Add) $ derivation $ props m
            return [(lbl,ExprScope $ ProgressProp new_prop Local li)]

instance IsEvtExpr Witness where
    defaultEvtWitness _ _ = return []
    toMchScopeExpr _ w   
        | w^.declSource == Local = return [Right $ PInitWitness (w^.ES.var) (w^.evtExpr)]
        | otherwise              = return []
    toEvtScopeExpr Old _ _ _ = return []
    toEvtScopeExpr New evt _ w
        | w^.declSource == Local = return [Right (evt,[EWitness (w^.ES.var) (getExpr $ w^.evtExpr)])]
        | otherwise              = return []
    setSource _ x = x
    inheritedFrom _ = []
    -- parseEvtExpr xs = do
    --     let toExpr = (_witnessVar &&& view evtExpr) . snd
    --         -- isLocal x = x ^. declSource == Local
    --         getLocalExpr = mapA (second $ Kleisli $ is_local) >>> arr (map toExpr)
    --         withEvent    = Kleisli id
    --         withoutEvent = Kleisli $ guard . MM.isNothing
    --         xs' = MM.mapMaybe (runKleisli $ withEvent *** getLocalExpr) xs
    --         ys' = MM.mapMaybe (runKleisli $ withoutEvent *** getLocalExpr >>> arr snd) xs
    --     pWitness %= doubleUnion xs'
    --     pInitWitness %= M.union (M.fromList $ concat ys')

instance IsEvtExpr ActionDecl where
    defaultEvtWitness ev (view inhStatus -> InhDelete (Just (_,act))) = do
            vs <- view pDelVars
            return [Right $ (ev,[EWitness v (ba_pred act) 
                                         | v <- M.elems $ frame' act `M.intersection` vs ])]
    defaultEvtWitness _ _ = return []
    toMchScopeExpr _ _  = return []
    toEvtScopeExpr =
            parseEvtExpr' "action"
                (uncurry M.union . (frame' &&& symbol_table.S.toList.used_var.ba_pred))
                EActions
            -- vs <- view pDelVars
            -- _
            -- concat <$> sequence 
            --     [ case act of
            --           Action (InhDelete (Just act)) Local _ _ -> _
            --               where f = frame' act `M.intersection` vs
            --                     ns = [ (lbl,Witness v (ba_pred act) Local undefined []) | v <- M.elems f ]
                -- ]
--     parseEvtExpr xs = do
--             parseEvtExprChoice' pOldActions pDelActions pNewActions fst xs
--             vs <- gets $ view pDelVars
--             let xs' = map (uncurry $ \k -> (k,) . concat . MM.mapMaybe (g k)) xs
--                 g (Just _) (lbl,Action (InhDelete (Just act)) Local _ _) = do
--                         let f = frame' act `M.intersection` vs
--                             ns = [ (lbl,Witness v (ba_pred act) Local undefined []) | v <- M.elems f ]
--                         return ns
--                 g _ _ = Nothing
--             parseEvtExprDefault pWitness (_witnessVar . snd) xs'
--             checkLocalExpr "action" 
--                (uncurry M.union . (frame' &&& used_var' . ba_pred)) 
--                 xs

newtype Compose3 f g h a = Compose3 { getCompose3 :: f (g (h a)) }
    deriving (Functor)

instance (Applicative f,Applicative g,Applicative h) => Applicative (Compose3 f g h) where
    pure = Compose3 . pure.pure.pure
    Compose3 f <*> Compose3 x = Compose3 $ uncomp $ comp f <*> comp x
        where
            comp = Compose . Compose
            uncomp = getCompose . getCompose

instance IsExprScope EventExpr where
    toNewEvtExprDefault _ (EventExpr m) = 
          fmap (concat.M.elems) 
        $ M.traverseWithKey defaultEvtWitness 
        $ M.mapKeysMonotonic fromRight' 
        $ M.filterWithKey (const.isRight) m
    toMchExpr lbl (EventExpr m) = 
            fmap concat $ mapM (toMchScopeExpr lbl) $ M.elems 
                $ M.filterWithKey (const.isLeft) m
    toThyExpr _ _  = return []
    toNewPropSet _ _ = return []
    toOldPropSet _ _ = return []
    toNewEvtExpr lbl (EventExpr m) =
            fmap concat $ mapM g $ rights $ map f $ M.toList m
        where f (x,y) = (,y) <$> x
              g (x,y) = toEvtScopeExpr New x lbl y
    toOldEvtExpr lbl (EventExpr m) = do
            concat <$> mapM fields (rights $ map f $ M.toList m)
        where f (x,y) = (,y) <$> x
              fields :: (EventId, EvtExprScope)
                     -> Reader MachineP2 [Either Error (EventId, [EventP3Field])]
              fields (x,y) = toEvtScopeExpr Old x lbl y
--     parseExpr xs = mapM_ (readEvtExprGroup parseEvtExpr) zs
--         where
--             ys = concatMap g xs
--             zs = groupEvtExprGroup (++) ys
--             g (lbl,EventExpr m) = M.elems $ M.mapWithKey (\eid -> readEvtExprScope $ \e -> EvtExprGroup [(eid,[(lbl,e)])]) m

init_witness_decl :: MPipeline MachineP2 [(Label,ExprScope)]
init_witness_decl = machineCmd "\\initwitness" $ \(String var, xp) _m p2 -> do
            -- ev <- get_event p2 evt
            li <- lift ask
            p  <- parse_expr'' (p2^.pMchSynt) xp
            v  <- bind (format "'{0}' is not a disappearing variable" var)
                (var `M.lookup` (L.view pAbstractVars p2 `M.difference` L.view pStateVars p2))
            return [(label var, ExprScope $ EventExpr $ M.singleton (Left InitEvent) (EvtExprScope $ Witness v p Local li))]

event_parser :: HasMachineP2 phase events => phase events thy -> EventId -> ParserSetting
event_parser p2 ev = (p2 ^. pEvtSynt) ! ev

schedule_parser :: HasMachineP2 phase events => phase events thy -> EventId -> ParserSetting
schedule_parser p2 ev = (p2 ^. pSchSynt) ! ev








machine_events :: HasMachineP1 phase events => phase events thy -> Map Label EventId
machine_events p2 = L.view pEventIds p2

evtScope :: IsEvtExpr a => EventId -> a -> ExprScope
evtScope ev x = ExprScope $ EventExpr $ M.singleton (Right ev) (EvtExprScope x)

addEvtExpr :: IsEvtExpr a
           => W.WriterT [(UntypedExpr,[String])] M (EventId,[(UntypedExpr,[String])] -> a) 
           -> M ExprScope
addEvtExpr m = do
    ((ev,f),w) <- W.runWriterT m
    return $ evtScope ev (f w)

check_types :: Either [String] a -> EitherT [Error] (RWS LineInfo [Error] ()) a    
check_types c = EitherT $ do
    li <- ask
    return $ either (\xs -> Left $ map (`Error` li) xs) Right c

free_vars' :: Map String Var -> Expr -> Map String Var
free_vars' ds e = vs `M.intersection` ds
    where
        vs = used_var' e

defaultInitWitness :: MachineP2 -> [MachineP3'Field a b] -> [MachineP3'Field a b]
defaultInitWitness p2 xs = concatMap f xs ++ xs
    where
        vs = p2^.pDelVars
        f (PDelInits _lbl expr) = [PInitWitness v expr
                                    | v <- M.elems $ used_var' expr `M.intersection` vs ]
        f _ = []
