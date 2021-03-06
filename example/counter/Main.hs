-- 参考：http://d.hatena.ne.jp/haxis_fx/20110726/1311657175

{-# LANGUAGE Arrows #-}
{-# LANGUAGE RankNTypes #-}
module
    Main
where

import qualified Control.Arrow.Machine as P
import Control.Applicative ((<$>), (<*>))
import qualified Control.Category as Cat
import Control.Arrow
import Control.Monad.State
import Control.Monad
import Control.Monad.Trans
import Debug.Trace

counter = 
    proc ev -> 
      do
        rec output <- returnA -< (\reset -> if reset then 0 else next) <$> ev
            next <- P.dHold 0 -< (+1) <$> output
        returnA -< output  

main = print $ P.run counter (map b "ffffffffttfftt")
  where b 't' = True
        b 'f' = False
