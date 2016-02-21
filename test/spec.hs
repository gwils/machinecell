{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE Arrows #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE FlexibleContexts #-}

module
    Main
where

import Data.Maybe (fromMaybe)
import qualified Control.Arrow.Machine as P
import Control.Arrow.Machine hiding (filter, source)
import Control.Applicative ((<$>), (<*>), (<$))
import qualified Control.Category as Cat
import Control.Arrow
import Control.Monad.State
import Control.Monad
import Control.Monad.Trans
import Control.Monad.Identity (Identity, runIdentity)
import Debug.Trace
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck (Arbitrary, arbitrary, oneof, frequency, sized)
import RandomProc
import LoopUtil
runKI a x = runIdentity (runKleisli a x)



main = hspec $
  do
    basics
    rules
    loops
    choice
    plans
    utility
    switches
    source
    execution
    loopUtil


basics =
  do
    describe "ProcessA" $
      do
        it "is stream transducer." $
          do
            let
              process = repeatedly $
                do
                  x <- await
                  yield x
                  yield (x + 1)

              resultA = run process [1,2,4]

            resultA `shouldBe` [1, 2, 2, 3, 4, 5]

        let
            -- 入力1度につき同じ値を2回出力する
            doubler = repeatedly $
                      do {x <- await; yield x; yield x}
            -- 入力値をStateのリストの先頭にPushする副作用を行い、同じ値を出力する
            pusher = repeatedlyT (Kleisli . const) $
                     do {x <- await; lift $ modify (x:); yield x}

        it "has stop state" $
          let
              -- 一度だけ入力をそのまま出力し、すぐに停止する
              onlyOnce = construct $ await >>= yield

              x = stateProc (doubler >>> pusher >>> onlyOnce) [3, 3]
            in
              -- 最後尾のMachineが停止した時点で処理を停止するが、
              -- 既にa2が出力した値の副作用は処理する
              x `shouldBe` ([3], [3, 3])

        it "has side-effect" $
          let
              incl = arr $ fmap (+1)

              -- doublerで信号が2つに分岐する。
              -- このとき、副作用は1つ目の信号について末尾まで
              -- -> 二つ目の信号について分岐点から末尾まで ...
              -- の順で処理される。
              a = pusher >>> doubler >>> incl >>> pusher >>> incl >>> pusher

              x = stateProc a [1000]
            in
              x `shouldBe` ([1002, 1002], reverse [1000,1001,1002,1001,1002])

        it "never spoils any FEED" $
          let
              counter = construct $ counterDo 1
              counterDo n =
                do
                  x <- await
                  yield $ n * 100 + x
                  counterDo (n+1)
              x = stateProc (doubler >>> doubler >>> counter) [1,2]
            in
              fst x `shouldBe` [101, 201, 301, 401, 502, 602, 702, 802]

        prop "each path can have independent number of events" $ \l ->
          let
              split2' = fmap fst &&& fmap snd
              gen = arr (fmap $ \x -> [x, x]) >>> fork >>> arr split2'
              r1 = runKI (run (gen >>> arr fst)) (l::[(Int, [Int])])
              r2 = runKI (run (gen >>> second (fork >>> echo) >>> arr fst))
                   (l::[(Int, [Int])])
            in
              r1 == r2


rules =
  do
    describe "ProcessA as Category" $
      do
        prop "has asocciative composition" $ \fx gx hx cond ->
          let
              f = mkProc fx
              g = mkProc gx
              h = mkProc hx
              equiv = mkEquivTest cond
            in
              ((f >>> g) >>> h) `equiv` (f >>> (g >>> h))

        prop "has identity" $ \fx gx cond ->
          let
              f = mkProc fx
              g = mkProc gx
              equiv = mkEquivTest cond
            in
              (f >>> g) `equiv` (f >>> Cat.id >>> g)

    describe "ProcessA as Arrow" $
      do
        it "can be made from pure function(arr)" $
          do
            (run . arr . fmap $ (+ 2)) [1, 2, 3]
              `shouldBe` [3, 4, 5]

        prop "arr id is identity" $ \fx gx cond ->
          let
              f = mkProc fx
              g = mkProc gx
              equiv = mkEquivTest cond
            in
              (f >>> g) `equiv` (f >>> arr id >>> g)

        it "can be parallelized" $
          do
            pendingWith "to correct"
{-
            let
                myProc2 = repeatedlyT (Kleisli . const) $
                  do
                    x <- await
                    lift $ modify (++ [x])
                    yield `mapM` (take x $ repeat x)

                toN = evMaybe Nothing Just
                en (ex, ey) = Event (toN ex, toN ey)
                de evxy = (fst <$> evxy, snd <$> evxy)

                l = map (\x->(x,x)) [1,2,3]

                (result, state) =
                    stateProc (arr de >>> first myProc2 >>> arr en) l

            (result >>= maybe mzero return . fst)
                `shouldBe` [1,2,2,3,3,3]
            (result >>= maybe mzero return . snd)
                `shouldBe` [1,2,3]
            state `shouldBe` [1,2,3]
-}

        prop "first and composition." $ \fx gx cond ->
          let
              f = mkProc fx
              g = mkProc gx
              equiv = mkEquivTest2 cond
            in
              (first (f >>> g)) `equiv` (first f >>> first g)

        prop "first-second commutes" $  \fx cond ->
          let
              f = first $ mkProc fx
              g = second (arr $ fmap (+2))

              equiv = mkEquivTest2 cond
            in
              (f >>> g) `equiv` (g >>> f)

        prop "first-fst commutes" $  \fx cond ->
          let
              f = mkProc fx
              equiv = mkEquivTest cond
                    ::(MyTestT (Event Int, Event Int) (Event Int))
            in
              (first f >>> arr fst) `equiv` (arr fst >>> f)

        prop "assoc relation" $ \fx cond ->
          let
              f = mkProc fx
              assoc ((a,b),c) = (a,(b,c))

              equiv = mkEquivTest cond
                    ::(MyTestT ((Event Int, Event Int), Event Int)
                               (Event Int, (Event Int, Event Int)))
            in
              (first (first f) >>> arr assoc) `equiv` (arr assoc >>> first f)

loops =
  do
    describe "ProcessA as ArrowLoop" $
      do
        it "can be used with rec statement(pure)" $
          let
              a = proc ev ->
                do
                  x <- hold 0 -< ev
                  rec l <- returnA -< x:l
                  returnA -< l <$ ev
              result = fst $ stateProc a [2, 5]
            in
              take 3 (result!!1) `shouldBe` [5, 5, 5]

        it "the last value is valid." $
          do
            let
                mc = repeatedly $
                  do
                    x <- await
                    yield x
                    yield (x*2)
                pa = proc x ->
                  do
                    rec y <- mc -< (+z) <$> x
                        z <- dHold 0 -< y
                    returnA -< y
            run pa [1, 10] `shouldBe` [1, 2, 12, 24]

        it "carries no events to upstream." $
          do
            let
                pa = proc ev ->
                  do
                    rec r <- dHold True -< False <$ ev2
                        ev2 <- fork -< [(), ()] <$ ev
                    returnA -< r <$ ev
            run pa [1, 2, 3] `shouldBe` [True, True, True]


    describe "Rules for ArrowLoop" $
      do
        let
            fixcore f y = if y `mod` 5 == 0 then y else y + f (y-1)
            pure (evx, f) = (f <$> evx, fixcore f)
            apure = arr pure

        prop "left tightening" $ \fx cond ->
          let
              f = mkProc fx

              equiv = mkEquivTest cond
            in
              (loop (first f >>> apure)) `equiv` (f >>> loop apure)

        prop "right tightening" $ \fx cond ->
          let
              f = mkProc fx

              equiv = mkEquivTest cond
            in
              (loop (apure >>> first f)) `equiv` (loop apure >>> f)


choice =
  do
    describe "ProcessA as ArrowChoice" $
      do
        it "temp1" $
         do
           let
                af = mkProc $ PgStop
                ag = mkProc $ PgOdd PgNop
                aj1 = arr Right
                aj2 = arr $ either id id
                l = [1]
                r1 = stateProc
                       (aj1 >>> left af >>> aj2)
                       l
              in
                r1 `shouldBe` ([1],[])

        prop "left (f >>> g) = left f >>> left g" $ \fx gx cond ->
            let
                f = mkProc fx
                g = mkProc gx

                equiv = mkEquivTest cond
                    ::(MyTestT (Either (Event Int) (Event Int))
                               (Either (Event Int) (Event Int)))
              in
                (left (f >>> g)) `equiv` (left f >>> left g)


plans = describe "Plan" $
  do
    let pl =
          do
            x <- await
            yield x
            yield (x+1)
            x <- await
            yield x
            yield (x+1)
        l = [2, 5, 10, 20, 100]

    it "can be constructed into ProcessA" $
      do
        let
            result = run (construct pl) l
        result `shouldBe` [2, 3, 5, 6]

    it "can be repeatedly constructed into ProcessA" $
      do
        let
            result = run (repeatedly pl) l
        result `shouldBe` [2, 3, 5, 6, 10, 11, 20, 21, 100, 101]

    it "can handle the end with catchP." $
      do
        let
            plCatch =
              do
                x <- await `catchP` (yield 1 >> stop)
                yield x
                y <- (yield 2 >> await >> yield 3 >> await) `catchP` (yield 4 >> return 5)
                yield y
                y <- (await >>= yield >> stop) `catchP` (yield 6 >> return 7)
                yield y
        run (construct plCatch) [] `shouldBe` [1]
        run (construct plCatch) [100] `shouldBe` [100, 2, 4, 5, 6, 7]
        run (construct plCatch) [100, 200] `shouldBe` [100, 2, 3, 4, 5, 6, 7]
        run (construct plCatch) [100, 200, 300] `shouldBe` [100, 2, 3, 300, 6, 7]
        run (construct plCatch) [100, 200, 300, 400] `shouldBe` [100, 2, 3, 300, 400, 6, 7]

utility =
  do
    describe "edge" $
      do
        it "detects edges of input behaviour" $
          do
            run (hold 0 >>> edge) [1, 1, 2, 2, 2, 3] `shouldBe` [0, 1, 2, 3]
            run (hold 0 >>> edge) [0, 1, 1, 2, 2, 2, 3] `shouldBe` [0, 1, 2, 3]

    describe "accum" $
      do
        it "acts like fold." $
          do
            let
                pa = proc evx ->
                  do
                    val <- accum 0 -< (+1) <$ evx
                    returnA -< val <$ evx

            run pa (replicate 10 ()) `shouldBe` [1..10]

    describe "onEnd" $
      do
        it "fires only once at the end of a stream." $
          do
            let
                pa = proc evx ->
                  do
                    x <- hold 0 -< evx
                    ed <- onEnd -< evx
                    returnA -< x <$ ed
            run pa [1..4] `shouldBe` [4]

    describe "gather" $
      do
        it "correctly handles the end" $
          do
            let
                pa = proc x ->
                  do
                    r1 <- P.filter $ arr (\x -> x `mod` 3 == 0) -< x
                    r2 <- stopped -< x::Event Int
                    r3 <- returnA -< r2
                    fin <- gather -< [r1, r2, r3]
                    val <- hold 0 -< r1
                    end <- onEnd -< fin
                    returnA -< val <$ end
            run pa [1, 2, 3, 4, 5] `shouldBe` ([3]::[Int])


switches =
  do
    describe "switch" $
      do
        it "switches once" $
          do
            let
                before = proc evx ->
                  do
                    ch <- P.filter (arr $ (\x -> x `mod` 2 == 0)) -< evx
                    returnA -< (noEvent, ch)

                after t = proc evx -> returnA -< (t*) <$> evx

                l = [1,3,4,1,3,2]

                -- 最初に偶数が与えられるまでは、入力を無視(NoEvent)し、
                -- それ以降は最初に与えられた偶数 * 入力値を返す
                ret = run (switch before after) l

                -- dが付くと次回からの切り替えとなる
                retD = run (dSwitch before after) l

            ret `shouldBe` [16, 4, 12, 8]
            retD `shouldBe` [4, 12, 8]

    describe "rSwitch" $
      do
        it "switches any times" $
          do
            let
               theArrow sw = proc evtp ->
                 do
                   evx <- P.fork -< fst <$> evtp
                   evarr <- P.fork -< snd <$> evtp
                   sw (arr $ fmap (+2)) -< (evx, evarr)

               l = [(Just 5, Nothing),
                    (Just 1, Just (arr $ fmap (*2))),
                    (Just 3, Nothing),
                    (Just 6, Just (arr $ fmap (*3))),
                    (Just 7, Nothing)]
               ret = run (theArrow rSwitch) l
               retD = run (theArrow drSwitch) l

            ret `shouldBe` [7, 2, 6, 18, 21]
            retD `shouldBe` [7, 3, 6, 12, 21]
    describe "kSwitch" $
      do
        it "switches spontaneously" $
          do
            let
                oneshot x = pure () >>> blockingSource [x]
                theArrow sw = sw (oneshot False) (arr snd) $ \_ _ -> oneshot True
            run (theArrow kSwitch) [] `shouldBe` [True]
            run (theArrow dkSwitch) [] `shouldBe` [False, True]

 source =
  do
    describe "source" $
      do
        it "provides interleaved source stream" $
          do
            let
                pa = proc cl ->
                  do
                    s1 <- P.source [1, 2, 3] -< cl
                    s2 <- P.source [4, 5, 6] -< cl
                    P.gather -< [s1, s2]
            P.run pa (repeat ()) `shouldBe` [1, 4, 2, 5, 3, 6]
    describe "blockingSource" $
      do
        it "provides blocking source stream" $
          do
            let
                pa = proc _ ->
                  do
                    s1 <- P.blockingSource [1, 2, 3] -< ()
                    s2 <- P.blockingSource [4, 5, 6] -< ()
                    P.gather -< [s1, s2]
            P.run pa (repeat ()) `shouldBe` [4, 5, 6, 1, 2, 3]

    describe "source and blockingSource" $
      do
        prop "[interleave blockingSource = source]" $ \l cond ->
            let
                _ = l::[Int]
                equiv = mkEquivTest cond
                    ::(MyTestT (Event Int) (Event Int))
              in
                P.source l `equiv` P.interleave (P.blockingSource l)

        prop "[blocking source = blockingSource]" $ \l cond ->
            let
                _ = l::[Int]
                equiv = mkEquivTest cond
                    ::(MyTestT (Event Int) (Event Int))
              in
                (pure () >>> P.blockingSource l)
                    `equiv` (pure () >>> P.blocking (P.source l))


execution = describe "Execution of ProcessA" $
    do
      let
          pl =
            do
              x <- await
              yield x
              yield (x+1)
              x <- await
              yield x
              yield (x+1)
              yield (x+5)
          init = construct pl

      it "supports step execution" $
        do
          let
              (ret, now) = stepRun init 1
          yields ret `shouldBe` [1, 2]
          hasStopped ret `shouldBe` False

          let
              (ret, now2) = stepRun now 1
          yields ret `shouldBe` [1, 2, 6]
          hasStopped ret `shouldBe` True

          let
              (ret, _) = stepRun now2 1
          yields ret `shouldBe` ([]::[Int])
          hasStopped ret `shouldBe` True

      it "supports step execution (2)" $
          pendingWith "Correct stop handling"
{-
      prop "supports step execution (2)" $ \p l ->
          let
              pa = mkProc p
              all pc (x:xs) ys =
                do
                  (r, cont) <- runKleisli (stepRun pc) x
                  all cont (if hasStopped r then [] else xs) (ys ++ yields r)
              all pc [] ys = runKleisli (run pc) [] >>= return . (ys++)
            in
              runState (all pa (l::[Int]) []) [] == stateProc pa l
-}

      it "supports yield-driven step" $
        do
          let
              init = construct $
                do
                  yield (-1)
                  x <- await
                  mapM yield (iterate (+1) x) -- infinite

              (ret, now) = stepYield init 5
          yields ret `shouldBe` Just (-1)
          hasConsumed ret `shouldBe` False
          hasStopped ret `shouldBe` False

          let
              (ret, now2) = stepYield now 10
          yields ret `shouldBe` Just 10
          hasConsumed ret `shouldBe` True
          hasStopped ret `shouldBe` False

          let
              (ret, now3) = stepYield now2 10
          yields ret `shouldBe` Just 11
          hasConsumed ret `shouldBe` False
          hasStopped ret `shouldBe` False

