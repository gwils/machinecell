{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE Arrows #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
module
    Main
where

import qualified Control.Arrow.Machine as P
import Control.Applicative ((<$>), (<*>), (<$))
import qualified Control.Category as Cat
import Control.Arrow
import Control.Arrow.ArrowIO
import Control.Monad
import Debug.Trace

import qualified Graphics.UI.WX as Wx
import Graphics.UI.WX (Prop ((:=)))
import qualified Graphics.UI.WXCore as WxC

import qualified WxHandler as WxP

type MainArrow = Kleisli IO
runMainArrow = runKleisli
instance ArrowIO MainArrow
  where
    arrIO = Kleisli


data MyForm a b c = MyForm { 
      myFormF :: Wx.Frame a,
      myFormBtnDlg :: Wx.Button b,
      myFormBtnQuit :: Wx.Button c
}
machine = proc world ->
  do
    initMsg <- WxP.onInit -< world
    form <- P.anyTime (arrIO0 setup) -< initMsg

    (returnA -< form) `P.passRecent` \(MyForm f btnDlg btnQuit) ->
      do    
        dialogMsg <- WxP.onCommand -< (world, btnDlg)
        P.anyTime (arrIO (\f -> Wx.infoDialog f "Hello" "Hello")) 
                -< f <$ dialogMsg

        quitMsg <- WxP.onCommand -< (world, btnQuit)
        P.anyTime (arrIO Wx.close) -< f <$ quitMsg


  where
    setup = 
      do
        f <- Wx.frame [Wx.text := "Hello!"]
        btnDialog <- Wx.button f [Wx.text := "Show Dialog"]
        btnQuit <- Wx.button f [Wx.text := "Quit"]
        Wx.set f [Wx.layout := Wx.column 5 
                        [Wx.widget btnDialog, Wx.widget btnQuit]]

        return $ MyForm f btnDialog btnQuit


main = 
  do
    WxP.wxReactimate runMainArrow machine