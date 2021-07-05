{-# LANGUAGE NoImplicitPrelude #-}
module Icicle.Internal.EditDistance (
    editDistance
  ) where

import           P hiding (head)
import           Icicle.Internal.Pretty
import           Data.List ((!!), head, tail, last)

editDistance :: Doc -> Doc -> Int
editDistance =
  let pretty_comp = display . renderCompact
  in  damerauLevenshtein `on` pretty_comp


-- | Calculate the Damerau-Levenshtein edit distance
--   between two lists (strings).
--
--   This function it from the optparse-applicative.
--   which was in turn modified from
--   https://wiki.haskell.org/Edit_distance
--   and is originally from Lloyd Allison's paper
--   "Lazy Dynamic-Programming can be Eager"
--
--   Complexity
--     O(|a|*(1 + editDistance a b))
damerauLevenshtein :: Eq a => [a] -> [a] -> Int
damerauLevenshtein a b =
  let
    mainDiag =
      oneDiag a b (head uppers) (-1 : head lowers)
    uppers =
      eachDiag a b (mainDiag : uppers) -- upper diagonals
    lowers =
      eachDiag b a (mainDiag : lowers) -- lower diagonals

    oneDiag a' b' diagAbove diagBelow = thisdiag
      where
        doDiag [] _ _ _ _ = []
        doDiag _ [] _ _ _ = []
        -- Check for a transposition
        -- We don't add anything to nw here, the next character
        -- will be different however and the transposition
        -- will have an edit distance of 1.
        doDiag (ach:ach':as) (bch:bch':bs) nw n w
          | ach' == bch && ach == bch'
          = nw : doDiag (ach' : as) (bch' : bs) nw (tail n) (tail w)
        -- Standard case
        doDiag (ach:as) (bch:bs) nw n w =
          let
            me =
              if ach == bch then
                nw
              else
                1 + min3 (head w) nw (head n)
          in
            me : doDiag as bs me (tail n) (tail w)

        firstelt = 1 + head diagBelow
        thisdiag = firstelt : doDiag a' b' firstelt diagAbove (tail diagBelow)

    eachDiag _ [] _ = []
    eachDiag _ _ [] = []
    eachDiag a' (_:bs) (lastDiag:diags) =
      let
        nextDiag = head (tail diags)
      in
        oneDiag a' bs nextDiag lastDiag : eachDiag a' bs diags

    lab =
      length a - length b

    min3 x y z =
      if x < y then
        x
      else
        min y z

  in
    last $
      if lab == 0 then
        mainDiag
      else if lab > 0 then
        lowers !! (lab - 1)
      else
        uppers !! (-1 - lab)
