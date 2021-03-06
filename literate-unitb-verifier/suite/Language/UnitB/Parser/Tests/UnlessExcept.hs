module Language.UnitB.Parser.Tests.UnlessExcept where

    -- Modules
import Language.UnitB.Parser.Tests.Suite

import           Data.Text (Text)
import qualified Data.Text as T

import Test.UnitTest

test_case :: TestCase
test_case = test

test :: TestCase
test = test_cases
            "Unless / except clause"
            [ (poCase "test 0, unless/except without indices" 
                (verify path0 0) result0)
            , (poCase "test 1, unless/except with indices and free variables" 
                (verify path0 1) result1)
            ]

path0 :: FilePath
path0 = [path|Tests/unless-except.tex|]

result0 :: Text
result0 = T.unlines
    [ "  o  m0/evt0/FIS/p@prime"
    , " xxx m0/evt0/SAF/saf1"
    , "  o  m0/evt1/FIS/p@prime"
    , "  o  m0/evt1/SAF/saf1"
    , "passed 3 / 4"
    ]

result1 :: Text
result1 = T.unlines
    [ "  o  m1/evt0/FIS/f@prime"
    , " xxx m1/evt0/SAF/saf1"
    , " xxx m1/evt0/WD/ACT/m0:act0"
    , "  o  m1/evt1/FIS/f@prime"
    , "  o  m1/evt1/SAF/saf1"
    , " xxx m1/evt1/WD/ACT/m0:act0"
    , " xxx m1/saf1/SAF/WD/lhs"
    , "passed 3 / 7"
    ]
