{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances  #-}
{-# LANGUAGE FlexibleContexts      #-}
module Utilities.Error where

import Utilities.Syntactic

import Control.Applicative

import Control.Monad.Identity
import Control.Monad.Reader.Class
import Control.Monad.State.Class
import Control.Monad.Trans
import Control.Monad.Trans.Either
import Control.Monad.Writer.Class

newtype ErrorT m a = ErrorT { runErrorT :: m (Either [Error] (a,[Error])) }

type ErrorM = ErrorT Identity

runErrorM :: ErrorT Identity a -> Either [Error] (a, [Error])
runErrorM = runIdentity . runErrorT

instance Monad m => Functor (ErrorT m) where
    fmap = liftM

instance Monad m => Applicative (ErrorT m) where
    f <*> x = ap f x
    pure x  = return x

instance (Monad m) => Monad (ErrorT m) where
    ErrorT cmd >>= f = ErrorT $ do
        x <- cmd
        case x of
            Right (x,ws) -> do
                x <- runErrorT (f x)
                case x of
                    Right (x,ws') -> return $ Right (x,ws++ws')
                    Left ws'      -> return $ Left $ ws ++ ws'
            Left ws -> 
                return $ Left ws
    return x = ErrorT $ return $ Right (x,[])

instance MonadTrans ErrorT where
    lift cmd = ErrorT $ do
            x <- cmd
            return $ Right (x,[])

instance Monad m => MonadWriter [Error] (ErrorT m) where
    tell w = ErrorT $ return $ Right ((),w)
    listen (ErrorT cmd) = ErrorT $ do
            x <- cmd
            case x of
                Right (x,ws) -> return $ Right ((x,ws),ws)
                Left ws -> return $ Left ws
    pass (ErrorT cmd) = ErrorT $ do
            x <- cmd
            case x of
                Right ((x,f),ws) -> return $ Right (x,f ws)
                Left ws -> return $ Left ws

class (Monad m) => MonadError m where
    soft_error :: [Error] -> m ()
    hard_error :: [Error] -> m a
    make_hard  :: m a -> m a
    make_soft  :: a -> m a -> m a

instance Monad m => MonadError (ErrorT m) where
    soft_error er = tell er
    
    hard_error er = ErrorT $ return $ Left er
            
    make_hard (ErrorT cmd) = ErrorT $ do
            y <- cmd
            case y of
                Right (y,w) 
                    | w == []   -> return $ Right (y,w)
                    | otherwise -> return $ Left w
                Left w ->  return $ Left w
    
    make_soft x (ErrorT cmd) = ErrorT $ do
            y <- cmd
            case y of
                Right (y,w) -> return $ Right (y,w)
                Left w ->  return $ Right (x,w)

fromEitherM :: MonadError m => EitherT [Error] m a -> m a
fromEitherM cmd = do
        x <- runEitherT cmd
        either hard_error return x
        
fromEitherT :: Monad m => EitherT [Error] m a -> ErrorT m a
fromEitherT cmd = ErrorT $ do
        x <- runEitherT cmd
        return $ either Left f x
    where
        f x = Right (x,[])

instance MonadReader a m => MonadReader a (ErrorT m) where
    ask = lift ask
    local f (ErrorT cmd) = ErrorT (local f cmd)
    
instance MonadState s m => MonadState s (ErrorT m) where
    get = lift get
    put x = lift $ put x

--instance (MonadTrans t, MonadError m) => MonadError (t m) where
--    soft_error x = lift $ soft_error x
--    hard_error x = lift $ hard_error x
--    make_hard m = lift $ 
--    make_soft  :: a -> m a -> m a
    
