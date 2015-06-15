{-# LANGUAGE Arrows #-}

module
    LoopUtil
where

import Data.Functor
import Control.Arrow
import Test.Hspec

import Control.Category ((>>>))

import Control.Arrow.Machine as P
import Control.Monad.Trans (liftIO)
import qualified Control.Arrow.Machine.Misc.Pump as Pump

doubler = arr (fmap $ \x -> [x, x]) >>> P.fork

loopUtil =
  do
    describe "cycleDelay" $
      do
        it "can refer a recent value at downstream." $
          do
            let 
                pa :: ProcessA (Kleisli IO) (Event Int) (Event Int)
                pa = proc evx ->
                  do
                    rec
                        y <- P.cycleDelay -< r2
                        anytime (Kleisli putStr) -< "" <$ evx -- side effect
                        evx2 <- doubler -< evx
                        r2 <- P.accum 0 -< (+) <$> evx2
                    returnA -< y <$ evx
            ret <- liftIO $ runKleisli (P.run pa) [1, 2, 3]
            ret `shouldBe` [0, 1+1, 1+1+2+2]
    describe "Pump" $
      do
        it "pumps up an event stream." $
          do
            let
                pa :: ProcessA (Kleisli IO) (Event Int) (Event Int)
                pa = proc evx ->
                  do
                    rec
                         evOut <- Pump.outlet -< (dct, () <$ evx)
                         anytime (Kleisli putStr) -< "" <$ evx -- side effect
                         so <- doubler -< evx
                         dct <- Pump.intake -< (so, () <$ evx)
                    returnA -< evOut

            ret <- liftIO $ runKleisli (P.run pa) [4, 5, 6]
            ret `shouldBe` [4, 4, 5, 5, 6, 6]
                    