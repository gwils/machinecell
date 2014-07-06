{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE Arrows #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE TypeSynonymInstances #-}

module
    Main
where

import qualified Control.Arrow.Machine as P
import Control.Applicative ((<$>), (<*>), (<$))
import qualified Control.Category as Cat
import Control.Arrow
import Control.Arrow.ArrowIO
import Control.Monad
import Control.Monad.Trans
import System.Random
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


data MyForm a = MyForm { 
      myFormF :: Wx.Frame a,
      myFormLabel :: Wx.StaticText a,
      myFormCounter :: Wx.StaticText a,
      myFormBtns :: [(Int, Wx.Button a)]
}


-- ボタンリストのイベント待機
onBtnAll :: (ArrowApply a, ArrowIO a) =>
    [(b, Wx.Button c)] -> P.ProcessA a (WxP.World a) (P.Event b)
onBtnAll btns = 
    P.gather <<< P.parB (make <$> btns)
  where
    make (num, btn) = proc world -> 
      do
        ev <- WxP.on0 Wx.command -< (world, btn)
        returnA -< num <$ ev


-- 処理の本体
machine = proc world ->
  do
    initMsg <- WxP.onInit -< world
    form <- P.anytime (arrIO0 setup) -< initMsg

    -- formが作成されたらgoにスイッチ
    P.switch 
            (arr $ \(_, f) -> (P.noEvent, f))
            go
        -< (world, form)

  where
    -- GUI初期化
    setup = 
      do
        f <- Wx.frame [Wx.text := "Take stones"]
        lbl <- Wx.staticText f [Wx.text := "A player who take the last stone will lose."]
        cntr <- Wx.staticText f [Wx.text := "000"]

        btns <- forM [1, 2, 3] $ \i ->
          do
            btn <- Wx.button f [Wx.text := show i]
            return (i, btn)

        Wx.set f [Wx.layout := Wx.column 5 
                        ([Wx.widget lbl, Wx.widget cntr] ++ (Wx.widget <$> snd <$> btns))]

        return $ MyForm f lbl cntr btns

    -- メインの処理
    go fm@(MyForm f lbl cntr btns) = proc (world, _) ->
        (\newNum -> P.hold (-1) -< newNum)
      `P.feedback` \numStones -> 
      do
        -- カウンタの更新
        newNumStones <- P.edge -< numStones
        P.anytime  
            (arrIO (\txt -> Wx.set cntr [Wx.text := show txt]))
                -< newNumStones

        -- ボタンから入力
        took <- onBtnAll btns -< world

        -- ゲームコルーチンを走らせる
        gameR <- game f -< (,) numStones <$> took

        -- メッセージの更新
        P.anytime  
            (arrIO (\txt -> Wx.set lbl [Wx.text := txt]))
                 -< snd <$> gameR

        -- ゲーム開始をハンドル(初期化時または決着時)
        newGameMsg <- P.filter (arr (<= 0)) <<< P.edge -< numStones
        initGame <- P.anytime (arrIO0 $ randomRIO (7, 30)) -< newGameMsg
        
        -- 新しい石の数をフィードバック
        gameRNum <- P.fork -< fst <$> gameR -- Maybeを消す
        newNum <- P.gather -< [gameRNum, initGame]
        returnA -< (P.noEvent, newNum) -- 第二引数をフィードバック


game f = P.constructT arrIO0 $
  do
    forever $
      do
        -- ボタン入力を待つ
        (n, youTook) <- P.await

        let 
            n' = n - youTook -- プレイヤーが取った後の石
            cpuTook' = (n' - 1) `mod` 4
            cpuTook = if cpuTook' == 0 then 1 else cpuTook' -- CPUが取る石
            nFin = if n' <= 0 then n' else n' - cpuTook
            msg = "You took " ++ show youTook ++ 
                if n' > 0 then ", cpu took" ++ show cpuTook ++ "."
                          else "."

        -- ここでyield(ラベルを更新してからダイアログを出すため)
        P.yield $ (Just nFin, msg)

        -- ダイアログの表示(別にコルーチンの中でする必要はないが、デモとして)
        if n' <= 0 then
          do
            lift $ Wx.infoDialog f "Game over" "You loose."
            P.yield (Nothing, "New game.")

          else if n' - cpuTook <= 0 then
          do
            lift $ Wx.infoDialog f "Game over" "You win."
            P.yield (Nothing, "New game.")

          else
            return ()
            



main = 
  do
    WxP.wxReactimate runMainArrow machine
