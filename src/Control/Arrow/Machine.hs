{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE Arrows #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE GADTs #-}
module
    Control.Arrow.Machine
      (
        -- * Modules
        module Event, 
        module Utils,
        module Plan,

        -- * The transducer arrow
        ProcessA(), 

        fit, 
        runProcessA, 
        stopped
       )
where

import Control.Arrow.Machine.Event as Event
import Control.Arrow.Machine.Utils as Utils
import Control.Arrow.Machine.Plan as Plan

import Control.Arrow.Machine.Types
