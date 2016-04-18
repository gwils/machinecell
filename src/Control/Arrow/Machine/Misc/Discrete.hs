{-# LANGUAGE Safe #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE Arrows #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}


module
    Control.Arrow.Machine.Misc.Discrete
      (
        -- * Discrete type
        -- $type

        T(),
        updates,
        value,

        arr,
        arr2,
        arr3,
        arr4,
        arr5,

        constant,
        unsafeConstant,
        hold,
        accum,
        fromEq,

        edge,
        asUpdater,
        kSwitch,
        dkSwitch,

        -- * Discrete algebra
        -- $alg

        Alg(Alg),
        eval,
        refer
      )
where

import Prelude hiding (id, (.))
import Control.Category
import Control.Arrow hiding (arr)
import Control.Applicative
import qualified Control.Arrow as Arr
import qualified Control.Arrow.Machine as P
import Data.Monoid (mconcat, mappend)

{-$type
This module should be imported manually. Qualified import is recommended.

This module provides an abstraction that continuous values with
finite number of changing points.

>>> import qualified Control.Arrow.Machine.Misc.Discrete as D
>>> run (D.hold "apple" >>> D.arr reverse >>> D.edge) ["orange", "grape"]
["elppa", "egnaro", "eparg"]

In above example, input data of "reverse" is continuous.
But the "D.edge" transducer extracts changing points without calling string comparison.

This is possible because the intermediate type `T` has the information of changes
together with the value information.
-}

-- |The discrete signal type.
data T a = T {
    updates :: (P.Event ()),
    value :: a
  }

makeT ::
    ArrowApply a =>
    P.ProcessA a (P.Event (), b) (T b)
makeT = Arr.arr $ uncurry T


stimulate ::
    ArrowApply a =>
    P.ProcessA a b (T c) ->
    P.ProcessA a b (T c)
stimulate sf = P.dgSwitch (id &&& id) sf body $ \sf' _ -> sf'
  where
    body = proc (dy, _) ->
      do
        n <- P.now -< ()
        disc <- makeT -< (updates dy `mappend` n, value dy)
        returnA -< (disc, updates disc)

arr ::
    ArrowApply a =>
    (b->c) ->
    P.ProcessA a (T b) (T c)
arr f =
    Arr.arr $ \(T ev x) ->
        T ev (f x)

arr2 ::
    ArrowApply a =>
    (b1->b2->c) ->
    P.ProcessA a (T b1, T b2) (T c)
arr2 f =
    Arr.arr $ \(T ev1 x1, T ev2 x2) ->
        T (mconcat [ev1, ev2]) (f x1 x2)

arr3 ::
    ArrowApply a =>
    (b1->b2->b3->c) ->
    P.ProcessA a (T b1, T b2, T b3) (T c)
arr3 f =
    Arr.arr $ \(T ev1 x1, T ev2 x2, T ev3 x3) ->
        T (mconcat [ev1, ev2, ev3]) (f x1 x2 x3)

arr4 ::
    ArrowApply a =>
    (b1->b2->b3->b4->c) ->
    P.ProcessA a (T b1, T b2, T b3, T b4) (T c)
arr4 f =
    Arr.arr $ \(T ev1 x1, T ev2 x2, T ev3 x3, T ev4 x4) ->
        T (mconcat [ev1, ev2, ev3, ev4]) (f x1 x2 x3 x4)

arr5 ::
    ArrowApply a =>
    (b1->b2->b3->b4->b5->c) ->
    P.ProcessA a (T b1, T b2, T b3, T b4, T b5) (T c)
arr5 f =
    Arr.arr $ \(T ev1 x1, T ev2 x2, T ev3 x3, T ev4 x4, T ev5 x5) ->
        T (mconcat [ev1, ev2, ev3, ev4, ev5]) (f x1 x2 x3 x4 x5)

constant::
    ArrowApply a =>
    c ->
    P.ProcessA a b (T c)
constant x =
    (P.now &&& Arr.arr (const x)) >>> makeT

-- |Constant without initial notifications.
-- Users must manage initialization manually.
unsafeConstant::
    ArrowApply a =>
    c ->
    P.ProcessA a b (T c)
unsafeConstant x =
    (pure P.noEvent &&& Arr.arr (const x)) >>> makeT

onUpdate ::
    ArrowApply a =>
    P.ProcessA a (P.Event b) (P.Event ())
onUpdate = proc ev ->
  do
    n <- P.now -< ()
    returnA -< n `mappend` P.collapse ev

hold ::
    ArrowApply a =>
    b ->
    P.ProcessA a (P.Event b) (T b)
hold i =
    (onUpdate &&& P.hold i) >>> makeT

accum ::
    ArrowApply a =>
    b ->
    P.ProcessA a (P.Event (b->b)) (T b)
accum i =
    (onUpdate &&& P.accum i) >>> makeT

fromEq ::
    (ArrowApply a, Eq b) =>
    P.ProcessA a b (T b)
fromEq = proc x ->
  do
    ev <- P.edge -< x
    returnA -< T (P.collapse ev) x

edge ::
    ArrowApply a =>
    P.ProcessA a (T b) (P.Event b)
edge = Arr.arr $ \(T ev x) -> x <$ ev

asUpdater ::
    ArrowApply a =>
    a b c ->
    P.ProcessA a (T b) (P.Event c)
asUpdater ar = edge >>> P.anytime ar


kSwitch ::
    ArrowApply a =>
    P.ProcessA a b (T c) ->
    P.ProcessA a (b, T c) (P.Event t) ->
    (P.ProcessA a b (T c) -> t -> P.ProcessA a b (T c)) ->
    P.ProcessA a b (T c)
kSwitch sf test k = P.kSwitch sf test (\sf' x -> stimulate (k sf' x))

dkSwitch ::
    ArrowApply a =>
    P.ProcessA a b (T c) ->
    P.ProcessA a (b, T c) (P.Event t) ->
    (P.ProcessA a b (T c) -> t -> P.ProcessA a b (T c)) ->
    P.ProcessA a b (T c)
dkSwitch sf test k = P.dkSwitch sf test (\sf' x -> stimulate (k sf' x))


{-$alg
Calculations between discrete types.

An example is below.

@
holdAdd ::
    (ArrowApply a, Num b) =>
    ProcessA a (Event b, Event b) (Discrete b)
holdAdd = proc (evx, evy) ->
  do
    x <- D.hold 0 -< evx
    y <- D.hold 0 -< evy
    D.eval (refer fst + refer snd) -< (x, y)
@

The last line is equivalent to "arr2 (+) -< (x, y)".
Using Alg, you can construct more complex calculations
between discrete signals.
-}

-- |Discrete algebra type.
newtype Alg a i o =
    Alg { eval :: P.ProcessA a i (T o) }

refer ::
    ArrowApply a =>
    (e -> T b) -> Alg a e b
refer = Alg . Arr.arr

instance
    ArrowApply a => Functor (Alg a i)
  where
    fmap f alg = Alg $ eval alg >>> arr f

instance
    ArrowApply a => Applicative (Alg a i)
  where
    pure = Alg . constant
    af <*> aa = Alg $ (eval af &&& eval aa) >>> arr2 ($)

instance
    (ArrowApply a, Num o) =>
    Num (Alg a i o)
  where
    abs = fmap abs
    signum = fmap signum
    fromInteger = pure . fromInteger
    (+) = liftA2 (+)
    (-) = liftA2 (-)
    (*) = liftA2 (*)

