module Interactive.Serialize where

    -- Modules
import Logic.Expr
import Logic.Proof

import UnitB.PO
import UnitB.Syntax as AST 
import UnitB.UnitB 

    -- Libraries
import Control.Applicative hiding (empty)
import Control.Arrow
import Control.DeepSeq
import Control.Lens hiding (Context)
import Control.Monad
import Control.Parallel.Strategies
import Control.Precondition
import Control.Monad.State

import Data.ByteString.Builder
import qualified Data.ByteString.Lazy as Lazy
import           Data.Either.Combinators
import           Data.Either.Validation
import           Data.Map.Class as M 
        ( insert 
        , fromList, toList
        , empty, mapKeys )
import qualified Data.Map.Class as M 
import           Data.Serialize as Ser ( Serialize(..), encodeLazy, decodeLazy ) 
import           Data.Serialize.Put 
import           Data.Tuple
import qualified Data.HashMap.Strict as H

import GHC.Generics (Generic)

import System.Directory
import System.IO.FileFormat

import Utilities.Table

type AbsIntMap a b = (a,[(b,Maybe Bool)])

data AbsFileStruct a b c = FileStruct { _seqs :: AbsIntMap a b, _exprs :: c }
    deriving (Generic)

makeLenses ''AbsFileStruct

{-# INLINABLE traverseKeys #-}
traverseKeys :: Traversal (AbsFileStruct a b c) (AbsFileStruct a' b c) a a'
traverseKeys = seqs._1

{-# INLINABLE traverseSeqIs #-}
traverseSeqIs :: Traversal (AbsFileStruct a b c) (AbsFileStruct a b' c) b b'
traverseSeqIs = seqs._2.traverse._1

{-# INLINABLE traverseExprTable #-}
traverseExprTable :: Traversal (AbsFileStruct a b c) (AbsFileStruct a b c') c c'
traverseExprTable = exprs

{-# INLINABLE traverseFileStruct #-}
traverseFileStruct :: Applicative f
                   => (a -> f a')
                   -> (b -> f b')
                   -> (c -> f c')
                   -> (AbsFileStruct a b c -> f (AbsFileStruct a' b' c'))
traverseFileStruct fA fB fC (FileStruct (a,b) c) = 
        FileStruct <$> liftA2 (,) 
                        (par $ fA a) 
                        (withStrategy (parList $ _1 rseq) <$> (traverse._1) fB b)
                   <*> par (fC c)
    where
        par = withStrategy rpar

{-# INLINE encodedFileStructPrism #-}
encodedFileStructPrism :: Prism' FileStructBin FileStruct
encodedFileStructPrism = prism 
        ( (traverseExprTable %~ par' . encodeLazy) 
        . (traverseKeys %~ par' . encodeLazy) 
        . (traverseSeqIs %~ par' . encodeLazy)) 
        (\x -> mapLeft (const x) . validationToEither $
            -- mapLeft (const x) . validationToEither $ 
             traverseFileStruct 
                (par' . decodeLazy') 
                (par' . decodeLazy') 
                (par' . decodeLazy') x )
    where
        par' :: NFData a => a -> a
        par' = withStrategy (rparWith rdeepseq)

{-# INLINABLE decodeLazy' #-}
decodeLazy' :: Serialize a 
            => Lazy.ByteString -> Validation () a
decodeLazy' = eitherToValidation . mapLeft (const ()) . decodeLazy

{-# INLINABLE seqFileFormat #-}
seqFileFormat :: FileFormat SeqTable
seqFileFormat = 
          failOnException 
        . compressedSequents
        . compressedFileFormat
        . serializedLazy
        . compressed
        $ lazyByteStringFile


{-# INLINABLE systemFileFormat #-}
systemFileFormat :: FileFormat (SeqTable,RawSystem)
systemFileFormat = 
          failOnException
        . prismFormat compressedSystemIso
        . serializedLazy
        . compressed
        $ lazyByteStringFile

type CompressedSystemPO = (M.Map Key (Maybe Bool),CompressedSystem)

{-# INLINABLE compressedSystemIso #-}
compressedSystemIso :: Prism' CompressedSystemPO (SeqTable, RawSystem)
compressedSystemIso = below compressingSystem
                    . iso (makePO &&& snd) (_1 %~ fmap snd)
    where
        makePO (m,sys) = M.intersectionWith (,) 
            (uncurryMap $ mapKeys as_label $ sys!.machines & traverse %~ proof_obligation)
            m

{-# INLINABLE compressedSequents' #-}
compressedSequents' :: err
                    -> FileFormat' err FileStruct
                    -> FileFormat' err (Table Key (Seq,Maybe Bool))
compressedSequents' err = prismFormat' (const err) intSequentIso

{-# INLINABLE compressedSequents #-}
compressedSequents :: FileFormat FileStruct
                   -> FileFormat (Table Key (Seq,Maybe Bool))
compressedSequents = prismFormat intSequentIso

{-# INLINABLE compressedFileFormat #-}
compressedFileFormat :: FileFormat FileStructBin
                     -> FileFormat FileStruct
compressedFileFormat = prismFormat encodedFileStructPrism

{-# INLINABLE compressedFileFormat' #-}
compressedFileFormat' :: err
                      -> FileFormat' err FileStructBin
                      -> FileFormat' err FileStruct
compressedFileFormat' err = prismFormat' (const err) encodedFileStructPrism

{-# INLINABLE intSequentIso #-}
intSequentIso :: Iso' FileStruct (Table Key (Seq,Maybe Bool))
intSequentIso = iso iseq_to_seq seq_to_iseq

expr_number :: Expr -> ExprStore Int
expr_number expr = do
    n <- gets $ M.lookup expr
    case n of
        Just n  -> return n
        Nothing -> do
            n <- gets M.size
            modify $ insert expr n
            return n

decompress_seq :: SeqI -> ExprIndex Seq
decompress_seq = traverse (gets . flip (!))
            
compress_seq :: Seq -> ExprStore SeqI
compress_seq = traverse expr_number

decompress_map :: IntMap -> ExprIndex (Table Key (Seq,Maybe Bool))
decompress_map ms = do
        xs <- forM (uncurry zip ms) $ \(x,(j,z)) -> do
            y <- decompress_seq j
            return (x,(y,z))
        return $ fromList xs

compress_map :: Table Key (Seq,Maybe Bool) -> ExprStore IntMap    
compress_map m = do
        xs <- forM (toList m) $ \(x,(y,z)) -> do
            j <- compress_seq y
            return (x,(j,z))
        return $ unzip xs
        
type Seq    = Sequent
type SeqI   = GenSequent Name Type HOQuantifier Int
-- type IntMap = [(Key,(SeqI,Bool))]
type IntMap = AbsIntMap [Key] SeqI
type IntMapBin = AbsIntMap Lazy.ByteString Lazy.ByteString
type ExprStore = State (H.HashMap Expr Int)
type ExprIndex = State (Table Int Expr)
type FileStruct = AbsFileStruct [Key] SeqI (H.HashMap Expr Int) 
type FileStructBin = AbsFileStruct Lazy.ByteString Lazy.ByteString Lazy.ByteString

load_pos :: FilePath 
         -> Table Key (Seq,Maybe Bool)
         -> IO (Table Key (Seq,Maybe Bool))
load_pos file pos = do
        let fname = file ++ ".state"
        b <- doesFileExist fname
        if b then do
            fromMaybe pos <$> readFormat seqFileFormat fname
        else return pos

instance (Serialize a,Serialize b,Serialize c) 
        => Serialize (AbsFileStruct a b c) where
    -- put (FileStruct (ks,seqs) ixs) = putBuilder $ 
    --         -- (parMconcatExponentialTree 5 xs)
    --             -- 22.9s
    --         -- (parMconcatExponentialTree 10 xs)
    --             -- 23.6s
    --         -- (parMconcatExponentialTree 20 xs)
    --             -- 23.4s
    --         -- (parMconcatExponentialTree 40 xs)
    --             -- 22.9s
    --         -- (parMconcat 5 xs)
    --             -- 24.97s
    --         -- (parMconcat 10 xs)
    --             -- 22.0s
    --         (parMconcat 20 xs)
    --             -- 21.9s
    --         -- (parMconcat 40 xs)
    --             -- 23.6s
    --         -- mconcat (xs  `using` parListChunk 5 rseq)
    --             -- 22.0s
    --         -- mconcat (xs  `using` parListChunk 10 rseq)
    --             -- 22.2s
    --         -- mconcat (xs  `using` parListChunk 20 rseq)
    --             -- 24.8s
    --         -- mconcat (xs  `using` parListChunk 40 rseq)
    --             -- 26.2s
    --     where
    --         xs = builderOfList ks ++ builderOfList seqs ++ builderOfList (toList ixs)

parMconcatExponentialTree :: Monoid a => Int -> [a] -> a
parMconcatExponentialTree ch xs = mconcat $ trees (length xs) ch xs
    where
        trees sz n xs 
                | sz <= n   = [runEval $ recurse sz xs]
                | otherwise = runEval (recurse n ys) : trees (sz - n) (ch * n) zs
            where
                (ys,zs) = splitAt n xs
        recurse n xs 
                | n <= ch   = rpar $ mconcat xs
                | otherwise = rpar =<< do
                        let k = n `div` ch
                            breakDown [] = []
                            breakDown xs = (length ys,ys) : breakDown zs
                                where
                                    (ys,zs) = splitAt k xs
                        rs <- mapM (uncurry recurse) (breakDown xs)
                        rseq $ mconcat rs

parMconcat :: Monoid a => Int -> [a] -> a
parMconcat chunk xs = mconcat (xs `using` aux n)
    where
        n = length xs
        aux :: Monoid a => Int -> Strategy [a]
        aux sz xs | sz >= 2*chunk = (:[]).mconcat <$> parListSplitAt half (aux half) (aux $ sz - half) xs
                  | otherwise     = return [mconcat xs]
            where
                half = sz `div` 2


builderOfList :: Serialize a => [a] -> [Builder]
builderOfList xs = execPut (putWord64be (fromIntegral (length xs))) : map (execPut . Ser.put) xs

iseq_to_seq :: FileStruct
            -> Table Key (Seq,Maybe Bool)
iseq_to_seq (FileStruct x y) = evalState (decompress_map x) inv
    where
        inv = fromList $ map swap $ toList $ y
        
seq_to_iseq :: Table Key (Seq,Maybe Bool)
            -> FileStruct 
seq_to_iseq pos = FileStruct a b
    where
        (a,b) = runState (compress_map pos) empty
        
dump_pos :: FilePath -> Table Key (Seq,Maybe Bool) -> IO ()
dump_pos file pos = do 
        let fn     = file ++ ".state"
        writeFormat seqFileFormat fn pos

dump_z3 :: Maybe Label -> FilePath -> Table Key (Seq,Maybe Bool) -> IO ()
dump_z3 pat file pos = dump file (M.map fst 
        $ M.filterWithKey (const . matches) 
        $ mapKeys snd pos)
    where
        matches = maybe (const True) (==) pat
