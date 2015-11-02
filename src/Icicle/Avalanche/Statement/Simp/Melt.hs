{-# LANGUAGE DoAndIfThenElse #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Icicle.Avalanche.Statement.Simp.Melt (
    melt
  , meltValue
  , unmeltValue
  ) where

import              Icicle.Avalanche.Prim.Flat
import              Icicle.Avalanche.Statement.Simp
import              Icicle.Avalanche.Statement.Statement

import qualified    Icicle.Common.Exp.Prim.Minimal as Min
import              Icicle.Common.Base
import              Icicle.Common.Exp
import              Icicle.Common.Fresh
import              Icicle.Common.Type
import              Icicle.Common.Annot

import              P

import qualified    Data.List           as List
import qualified    Data.Map            as Map
import qualified    Data.Tuple          as Tuple


------------------------------------------------------------------------

-- this could be shared between modules if it's useful?

pattern PrimZip     ta tb = PrimArray   (PrimArrayZip ta tb)
pattern PrimUnzip   ta tb = PrimArray   (PrimArrayUnzip ta tb)

pattern PrimSum     ta tb = PrimArray   (PrimArraySum ta tb)
pattern PrimUnsum   ta tb = PrimArray   (PrimArrayUnsum ta tb)

pattern PrimPair    ta tb = PrimMinimal (Min.PrimConst (Min.PrimConstPair ta tb))
pattern PrimFst     ta tb = PrimMinimal (Min.PrimPair  (Min.PrimPairFst   ta tb))
pattern PrimSnd     ta tb = PrimMinimal (Min.PrimPair  (Min.PrimPairSnd   ta tb))

pattern PrimMkOpt      tv = PrimPack    (PrimOptionPack          tv)
pattern PrimIsSome     tv = PrimProject (PrimProjectOptionIsSome tv)
pattern PrimGet        tv = PrimUnsafe  (PrimUnsafeOptionGet     tv)

pattern PrimMkSum   ta tb = PrimPack    (PrimSumPack           ta tb)
pattern PrimIsRight ta tb = PrimProject (PrimProjectSumIsRight ta tb)
pattern PrimLeft    ta tb = PrimUnsafe  (PrimUnsafeSumGetLeft  ta tb)
pattern PrimRight   ta tb = PrimUnsafe  (PrimUnsafeSumGetRight ta tb)

data MeltOps a n p = MeltOps {
    xPrim  :: p -> Exp a n p
  , xVar   :: Name n -> Exp a n p
  , xValue :: ValType   -> BaseValue -> Exp a n p
  , xApp   :: Exp a n p -> Exp a n p -> Exp a n p

  , primZip   :: ValType -> ValType -> Name n -> Name n -> Exp a n p
  , primUnzip :: ValType -> ValType -> Exp a n p -> Exp a n p

  , primSum   :: ValType -> ValType -> Name n -> Name n -> Name n -> Exp a n p
  , primUnsum :: ValType -> ValType -> Exp a n p -> Exp a n p

  , primPair :: ValType -> ValType -> Name n -> Name n -> Exp a n p
  , primFst  :: ValType -> ValType -> Exp a n p        -> Exp a n p
  , primSnd  :: ValType -> ValType -> Exp a n p        -> Exp a n p

  , primMkOpt  :: ValType -> Name n -> Name n -> Exp a n p
  , primIsSome :: ValType -> Exp a n p        -> Exp a n p
  , primGet    :: ValType -> Exp a n p        -> Exp a n p

  , primMkSum   :: ValType -> ValType -> Name n -> Name n -> Name n -> Exp a n p
  , primIsRight :: ValType -> ValType -> Exp a n p                  -> Exp a n p
  , primLeft    :: ValType -> ValType -> Exp a n p                  -> Exp a n p
  , primRight   :: ValType -> ValType -> Exp a n p                  -> Exp a n p

  , primBoolArray :: ValType -> Name n -> Exp a n p
  }

meltOps :: a -> MeltOps a n Prim
meltOps a_fresh
 = MeltOps{..}
 where
  xVar   = XVar   a_fresh
  xPrim  = XPrim  a_fresh
  xValue = XValue a_fresh
  xApp   = XApp   a_fresh

  primZip     ta tb x y   = xPrim (PrimZip     ta tb) `xApp` xVar x `xApp` xVar y
  primUnzip   ta tb x     = xPrim (PrimUnzip   ta tb) `xApp` x

  primSum     ta tb x y z = xPrim (PrimSum     ta tb) `xApp` xVar x `xApp` xVar y `xApp` xVar z
  primUnsum   ta tb x     = xPrim (PrimUnsum   ta tb) `xApp` x

  primPair    ta tb x y   = xPrim (PrimPair    ta tb) `xApp` xVar x `xApp` xVar y
  primFst     ta tb x     = xPrim (PrimFst     ta tb) `xApp` x
  primSnd     ta tb x     = xPrim (PrimSnd     ta tb) `xApp` x

  primMkOpt   tv b v      = xPrim (PrimMkOpt      tv) `xApp` xVar b `xApp` xVar v
  primIsSome  tv v        = xPrim (PrimIsSome     tv) `xApp` v
  primGet     tv v        = xPrim (PrimGet        tv) `xApp` v

  primMkSum   ta tb i x y = xPrim (PrimMkSum   ta tb) `xApp` xVar i `xApp` xVar x `xApp` xVar y
  primIsRight ta tb x     = xPrim (PrimIsRight ta tb) `xApp` x
  primLeft    ta tb x     = xPrim (PrimLeft    ta tb) `xApp` x
  primRight   ta tb x     = xPrim (PrimRight   ta tb) `xApp` x

  primBoolArray a x       = xPrim (PrimUnsafe (PrimUnsafeArrayCreate BoolT))
                            `xApp` (xPrim (PrimProject (PrimProjectArrayLength a))
                                    `xApp` xVar x)

------------------------------------------------------------------------

melt :: (Show n, Ord n)
     => Annot a
     -> Statement (Annot a) n Prim
     -> Fresh n (Statement (Annot a) n Prim)
melt a_fresh ss
 =   meltBindings     a_fresh ss
 >>= meltAccumulators a_fresh
 >>= meltForeachFacts a_fresh
 >>= meltOutputs      a_fresh

------------------------------------------------------------------------

meltAccumulators :: (Show n, Ord n)
                 => a
                 -> Statement a n Prim
                 -> Fresh n (Statement a n Prim)
meltAccumulators a_fresh statements
 = transformUDStmt goStmt Map.empty statements
 where
  MeltOps{..} = meltOps a_fresh

  goStmt env stmt
   = do env' <- updateEnv stmt env
        let go = goStmt env'
        case stmt of

          ----------------------------------------
          InitAccumulator (Accumulator n ak avt x) ss
           | Just (Latest, PairT ta tb, [na, nb])       <- Map.lookup n env'
           -> go
            . InitAccumulator (Accumulator na ak ta x)
            . InitAccumulator (Accumulator nb ak tb x)
            $ ss

           | Just (Mutable, PairT ta tb, [na, nb])      <- Map.lookup n env'
           -> go
            . InitAccumulator (Accumulator na ak ta (primFst ta tb x))
            . InitAccumulator (Accumulator nb ak tb (primSnd ta tb x))
            $ ss

           | Just (Mutable, OptionT tv, [nb, nv])       <- Map.lookup n env'
           , tb                                         <- BoolT
           -> go
            . InitAccumulator (Accumulator nb ak tb (primIsSome tv x))
            . InitAccumulator (Accumulator nv ak tv (primGet    tv x))
            $ ss

           | Just (Mutable, SumT ta tb, [ni, na, nb])   <- Map.lookup n env'
           , ti                                         <- BoolT
           -> go
            . InitAccumulator (Accumulator ni ak ti (primIsRight ta tb x))
            . InitAccumulator (Accumulator na ak ta (primLeft    ta tb x))
            . InitAccumulator (Accumulator nb ak tb (primRight   ta tb x))
            $ ss

{-
           | Just (Mutable, t, [na, nb]) <- Map.lookup n env'
           , Just (f, at)     <- takeFunctorType t
           , [ta, tb]         <- takeBinType at
           , ta'              <- f ta
           , tb'              <- f tb
           , [(xa,_), (xb,_)] <- meltExp a_fresh (primUnzip ta tb x) (PairT ta' tb')
           -> go
           -- InitAccumulator (Accumulator ni ak ti  (primBoolArray at n))
           . InitAccumulator (Accumulator na ak ta' xa)
           . InitAccumulator (Accumulator nb ak tb' xb)
           $ ss
-}

           | Just (Mutable, ArrayT (SumT ta tb), [na,nb]) <- Map.lookup n env'
           -> do (xs', _) <- meltBody a_fresh (n, avt, x)
                 go . foldr (mkInitAccum ak) id xs' $ ss

           | Just (Mutable, UnitT, [])                  <- Map.lookup n env'
           -> go ss

          ----------------------------------------
          Read n acc avt _ ss
           | Just (Latest, PairT ta tb, [na, nb])       <- Map.lookup acc env'
           -> do [na', nb'] <- freshes 2 n
                 ss' <- substXinS a_fresh n (primZip ta tb na' nb') ss
                 go . Read na' na avt ta
                    . Read nb' nb avt tb
                    $ ss'

           | Just (Mutable, PairT ta tb, [na, nb])      <- Map.lookup acc env'
           -> do [na', nb'] <- freshes 2 n
                 ss' <- substXinS a_fresh n (primPair ta tb na' nb') ss
                 go . Read na' na avt ta
                    . Read nb' nb avt tb
                    $ ss'

           | Just (Mutable, OptionT tv, [nb, nv])       <- Map.lookup acc env'
           , tb                                         <- BoolT
           -> do [nb', nv'] <- freshes 2 n
                 ss' <- substXinS a_fresh n (primMkOpt tv nb' nv') ss
                 go . Read nb' nb avt tb
                    . Read nv' nv avt tv
                    $ ss'

           | Just (Mutable, SumT ta tb, [ni, na, nb])   <- Map.lookup acc env'
           , ti                                         <- BoolT
           -> do [ni', na', nb'] <- freshes 3 n
                 ss' <- substXinS a_fresh n (primMkSum ta tb ni' na' nb') ss
                 go . Read ni' ni avt ti
                    . Read na' na avt ta
                    . Read nb' nb avt tb
                    $ ss'

           | Just (Mutable, t, [na, nb]) <- Map.lookup acc env'
           , Just (f, at)                <- takeFunctorType t
           , [ta, tb]                    <- takeBinType at
           , ta'                         <- f ta
           , tb'                         <- f tb
           -> do [na', nb'] <- freshes 3 n
                 ss' <- substXinS a_fresh n (primPair ta' tb' na' nb') ss
                 go . Read na' na avt ta'
                    . Read nb' nb avt tb'
                    $ ss'

           | Just (Mutable, UnitT, [])                  <- Map.lookup acc env'
           -> do ss' <- substXinS a_fresh n (xValue UnitT VUnit) ss
                 go ss'

          ----------------------------------------
          Push n x
           | Just (Latest, PairT ta tb, [na, nb])       <- Map.lookup n env'
           -> go
            $ Block [ Push na (primFst ta tb x)
                    , Push nb (primSnd ta tb x) ]

          ----------------------------------------
          Write n x
           | Just (Mutable, PairT ta tb, [na, nb])      <- Map.lookup n env'
           -> go
            $ Block [ Write na (primFst ta tb x)
                    , Write nb (primSnd ta tb x) ]

           | Just (Mutable, OptionT tv, [nb, nv])       <- Map.lookup n env'
           -> go
            $ Block [ Write nb (primIsSome tv x)
                    , Write nv (primGet    tv x) ]

           | Just (Mutable, SumT ta tb, [ni, na, nb])   <- Map.lookup n env'
           -> go
            $ Block [ Write ni (primIsRight ta tb x)
                    , Write na (primLeft    ta tb x)
                    , Write nb (primRight   ta tb x) ]

           | Just (Mutable, t, [na, nb]) <- Map.lookup n env'
           , Just (f, at)                <- takeFunctorType t
           , [ta, tb]                    <- takeBinType at
           , ta'                         <- f ta
           , tb'                         <- f tb
           -> go
            $ Block [ Write na (primFst ta' tb' x)
                    , Write nb (primSnd ta' tb' x) ]

           | Just (_, UnitT, _)                         <- Map.lookup n env'
           -> return (env', mempty)

          ----------------------------------------
          LoadResumable n _
           | Just (_, PairT ta tb, [na, nb])            <- Map.lookup n env'
           -> go
            $ Block [ LoadResumable na ta
                    , LoadResumable nb tb ]

           | Just (_, OptionT tv, [nb, nv])             <- Map.lookup n env'
           , tb                                         <- BoolT
           -> go
            $ Block [ LoadResumable nb tb
                    , LoadResumable nv tv ]

           | Just (_, SumT ta tb, [ni, na, nb])         <- Map.lookup n env'
           , ti                                         <- BoolT
           -> go
            $ Block [ LoadResumable ni ti
                    , LoadResumable na ta
                    , LoadResumable nb tb ]

           | Just (_, UnitT, [])                        <- Map.lookup n env'
           -> go
            $ Block []

          ----------------------------------------
          SaveResumable n _
           | Just (_, PairT ta tb, [na, nb])            <- Map.lookup n env'
           -> go
            $ Block [ SaveResumable na ta
                    , SaveResumable nb tb ]

           | Just (_, OptionT tv, [nb, nv])             <- Map.lookup n env'
           , tb                                         <- BoolT
           -> go
            $ Block [ SaveResumable nb tb
                    , SaveResumable nv tv ]

           | Just (_, SumT ta tb, [ni, na, nb])         <- Map.lookup n env'
           , ti                                         <- BoolT
           -> go
            $ Block [ SaveResumable ni ti
                    , SaveResumable na ta
                    , SaveResumable nb tb ]

           | Just (_, UnitT, [])                        <- Map.lookup n env'
           -> go
            $ Block []

          _
           -> return (env', stmt)


  updateEnv s env
   | InitAccumulator (Accumulator n Mutable UnitT _) _ <- s
   = return (Map.insert n (Mutable, UnitT, []) env)

   | InitAccumulator (Accumulator n at avt@(PairT _ _) _) _ <- s
   = two n at avt env
   | InitAccumulator (Accumulator n at avt@(OptionT _) _) _ <- s
   = two n at avt env

   | InitAccumulator (Accumulator n at avt@(SumT _ _) _) _ <- s
   = three n at avt env
   | InitAccumulator (Accumulator n at avt@(ArrayT (SumT _ _)) _) _ <- s
   = three n at avt env

   | otherwise
   = return env

  mkInitAccum ak (n, t, x) acc
   = InitAccumulator (Accumulator n ak t x) . acc

  two n at avt env
   = do nb <- freshPrefix' n
        nv <- freshPrefix' n
        return (Map.insert n (at, avt, [nb, nv]) env)

  three n at avt env
   = do ni <- freshPrefix' n
        na <- freshPrefix' n
        nb <- freshPrefix' n
        return $ Map.insert n (at, avt, [ni, na, nb]) env

  takeBinType (SumT ta tb) = [ta, tb]
  takeBinType _            = []

  takeFunctorType (ArrayT t) = Just (ArrayT, t)
  takeFunctorType (BufT   t) = Just (BufT,   t)
  takeFunctorType _          = Nothing

--------------------------------------------------------------------------------

-- | Melt the body of Let bindings into multiple bindings and substitute the
--   old binding with new ones.
--
meltBindings
  :: (Ord n)
  => Annot a
  -> Statement (Annot a) n Prim
  -> Fresh n (Statement (Annot a) n Prim)
meltBindings a_fresh statements
 = transformUDStmt goStmt () statements
 where
  MeltOps{..} = meltOps a_fresh

  goStmt () stmt
   = case stmt of
       Let n x ss
        | vt <- functionReturns (annType (annotOfExp x))
        -> do (xs, x') <- meltBody a_fresh (n, vt, x)
              ss'      <- substXinS a_fresh n x' ss
              let stmt' = foldr mkLet ss' xs
              --traceM $ "ORIGINAL:\n" <> show (pretty stmt) <> "\nAFTER:\n" <> show (pretty stmt')
              return ((), stmt')

       _ -> return ((), stmt)

  mkLet (n,_,x) s
   = Let n x s


meltBody
 :: a -> (Name n, ValType, Exp a n Prim) -> Fresh n ([(Name n, ValType, Exp a n Prim)], Exp a n Prim)
meltBody a_fresh (n, vt, x)
 = case vt of
    SumT ta tb
     -> do [bn,ln,rn] <- mkNames n vt
           (bx,bu)    <- meltBody a_fresh (bn, BoolT, primIsRight ta tb x)
           (lx,lu)    <- meltBody a_fresh (ln, ta,    primLeft    ta tb x)
           (rx,ru)    <- meltBody a_fresh (rn, tb,    primRight   ta tb x)
           let binds   = bx <> lx <> rx <> [(bn,BoolT,bu),(ln,ta,lu),(rn,tb,ru)]
           let unmelt  = primMkSum ta tb bn ln rn
           return (binds, unmelt)

    PairT ta tb
     -> do [ln,rn]    <- mkNames n vt
           (lx,lu)    <- meltBody a_fresh (ln, ta,    primFst ta tb x)
           (rx,ru)    <- meltBody a_fresh (rn, tb,    primSnd ta tb x)
           let binds   = lx <> rx <> [(ln,ta,lu),(rn,tb,ru)]
           let unmelt  = primPair ta tb ln rn
           return (binds, unmelt)

    ArrayT t@(SumT ta tb)
     -> do [bn,ln,rn] <- mkNames n t
           let x' = primUnsum ta tb x
               t1 = ArrayT BoolT
               t2 = PairT t3 t4
               t3 = ArrayT ta
               t4 = ArrayT tb
           (bx,bu)    <- meltBody a_fresh (bn, BoolT, primFst t1 t2 x')
           (lx,lu)    <- meltBody a_fresh (ln, ta,    primFst t3 t4 (primSnd t1 t2 x'))
           (rx,ru)    <- meltBody a_fresh (rn, tb,    primSnd t3 t4 (primSnd t1 t2 x'))
           let binds   = bx <> lx <> rx <> [(bn,BoolT,bu),(ln,ta,lu),(rn,tb,ru)]
           let unmelt  = primSum ta tb bn ln rn
           return (binds, unmelt)

    _ -> return ([(n, vt, x)], x)

 where
  MeltOps{..} = meltOps a_fresh


mkNames :: Name n -> ValType -> Fresh n [Name n]
mkNames n (SumT  _ _) = freshes 3 n
mkNames n (PairT _ _) = freshes 2 n
mkNames n (OptionT _) = freshes 2 n

------------------------------------------------------------------------

meltForeachFacts :: forall a n. (Show n, Ord n)
                 => a
                 -> Statement a n Prim
                 -> Fresh n (Statement a n Prim)
meltForeachFacts a_fresh statements
 = transformUDStmt goStmt () statements
 where
  MeltOps{..} = meltOps a_fresh

  goStmt () stmt
   = case stmt of
       ForeachFacts ns vt lt ss
        -> do (ns', ss') <- meltFix ns ss
              return ((), ForeachFacts ns' vt lt ss')
       _
        -> return ((), stmt)

  meltFix ns0 ss0 = do
    (ns1, ss1) <- meltFacts ns0 ss0
    if length ns0 /= length ns1
    then meltFix ns1 ss1
    else return (ns1, ss1)


  meltFacts :: [(Name n, ValType)]
            -> Statement a n Prim
            -> Fresh n ([(Name n, ValType)], Statement a n Prim)

  meltFacts []     ss0 = return ([], ss0)
  meltFacts (n:ns) ss0 = do
    (xs, ss1) <- meltFact  n  ss0
    (ys, ss2) <- meltFacts ns ss1
    return (xs <> ys, ss2)


  meltFact :: (Name n, ValType)
           -> Statement a n Prim
           -> Fresh n ([(Name n, ValType)], Statement a n Prim)

  meltFact (n, t) ss
   | PairT ta tb <- t
   = do na <- freshPrefix' n
        nb <- freshPrefix' n
        ss' <- substXinS a_fresh n (primPair ta tb na nb) ss
        let ns = [(na, ta), (nb, tb)]
        return (ns, ss')

   | OptionT tv <- t
   = do nb <- freshPrefix' n
        nv <- freshPrefix' n
        ss' <- substXinS a_fresh n (primMkOpt tv nb nv) ss
        let ns = [(nb, BoolT), (nv, tv)]
        return (ns, ss')

   | SumT ta tb <- t
   = do ni <- freshPrefix' n
        na <- freshPrefix' n
        nb <- freshPrefix' n
        ss' <- substXinS a_fresh n (primMkSum ta tb ni na nb) ss
        let ns = [(ni, BoolT), (na, ta), (nb, tb)]
        return (ns, ss')

   | otherwise
   = return ([(n, t)], ss)

------------------------------------------------------------------------

meltOutputs :: forall a n. (Show n, Ord n)
            => a
            -> Statement a n Prim
            -> Fresh n (Statement a n Prim)
meltOutputs a_fresh statements
 = transformUDStmt goStmt () statements
 where
  MeltOps{..} = meltOps a_fresh

  goStmt () stmt
   = case stmt of
       Output n t xts
        -> return ((), Output n t (meltExps a_fresh xts))
       _
        -> return ((), stmt)

meltExps :: a -> [(Exp a n Prim, ValType)] -> [(Exp a n Prim, ValType)]
meltExps a_fresh
 = concatMap (\(x,t) -> meltExp a_fresh x t)

meltExp :: a -> Exp a n Prim -> ValType -> [(Exp a n Prim, ValType)]
meltExp a_fresh x t
 = let MeltOps{..} = meltOps a_fresh
   in case t of
     IntT{}      -> [(x, t)]
     DoubleT{}   -> [(x, t)]
     UnitT{}     -> [(x, t)]
     BoolT{}     -> [(x, t)]
     DateTimeT{} -> [(x, t)]
     StringT{}   -> [(x, t)]
     ArrayT{}    -> [(x, t)]
     MapT{}      -> [(x, t)]
     StructT{}   -> [(x, t)]
     BufT{}      -> [(x, t)]
     ErrorT{}    -> [(x, t)]

     PairT ta tb
      -> meltExp a_fresh (primFst ta tb x) ta
      <> meltExp a_fresh (primSnd ta tb x) tb

     SumT ta tb
      -> meltExp a_fresh (primIsRight ta tb x) BoolT
      <> meltExp a_fresh (primLeft    ta tb x) ta
      <> meltExp a_fresh (primRight   ta tb x) tb

     OptionT tx
      -> meltExp a_fresh (primIsSome tx x) BoolT
      <> meltExp a_fresh (primGet    tx x) tx

------------------------------------------------------------------------

-- implementation should match `meltFact` above
meltValue :: BaseValue -> ValType -> Maybe [BaseValue]
meltValue v t
 = let apcat x y = (<>) <$> x <*> y
   in case v of
     VInt{}      -> Just [v]
     VDouble{}   -> Just [v]
     VUnit{}     -> Just [v]
     VBool{}     -> Just [v]
     VDateTime{} -> Just [v]
     VString{}   -> Just [v]
     VArray{}    -> Just [v]
     VMap{}      -> Just [v]
     VStruct{}   -> Just [v]
     VBuf{}      -> Just [v]
     VError{}    -> Just [v]

     VPair a b
      | PairT ta tb <- t
      -> meltValue a ta `apcat` meltValue b tb

      | otherwise
      -> Nothing

     VLeft a
      | SumT ta tb <- t
      -> pure [VBool False] `apcat` meltValue a ta `apcat` meltValue (defaultOfType tb) tb

      | otherwise
      -> Nothing

     VRight b
      | SumT ta tb <- t
      -> pure [VBool True] `apcat` meltValue (defaultOfType ta) ta `apcat` meltValue b tb

      | otherwise
      -> Nothing

     VNone
      | OptionT tv <- t
      -> pure [VBool False] `apcat` meltValue (defaultOfType tv) tv

      | otherwise
      -> Nothing

     VSome x
      | OptionT tx <- t
      -> pure [VBool True] `apcat` meltValue x tx

      | otherwise
      -> Nothing

freshes :: Int -> Name n -> Fresh n [Name n]
freshes i n
 = replicateM i $ freshPrefix' n

------------------------------------------------------------------------

unmeltValue :: [BaseValue] -> ValType -> Maybe BaseValue
unmeltValue vs t
 = case unmeltValue' vs t of
     Just (v, [])   -> Just v
     Nothing        -> Nothing

     -- if we still have values left over
     -- after unmelting, it's a type error
     Just (_v, _xs) -> Nothing

unmeltValue' :: [BaseValue] -> ValType -> Maybe (BaseValue, [BaseValue])
unmeltValue' []        _ = Nothing
unmeltValue' vs0@(v:vs) t
 = case t of
     IntT{}      -> Just (v, vs)
     DoubleT{}   -> Just (v, vs)
     UnitT{}     -> Just (v, vs)
     BoolT{}     -> Just (v, vs)
     DateTimeT{} -> Just (v, vs)
     StringT{}   -> Just (v, vs)
     ArrayT{}    -> Just (v, vs)
     MapT{}      -> Just (v, vs)
     StructT{}   -> Just (v, vs)
     BufT{}      -> Just (v, vs)
     ErrorT{}    -> Just (v, vs)

     PairT ta tb
      -> do (a, vs1) <- unmeltValue' vs0 ta
            (b, vs2) <- unmeltValue' vs1 tb
            Just (VPair a b, vs2)

     SumT ta tb
      -> do (i, vs1) <- unmeltValue' vs0 BoolT
            (a, vs2) <- unmeltValue' vs1 ta
            (b, vs3) <- unmeltValue' vs2 tb
            case i of
              VBool False -> Just (VLeft  a, vs3)
              VBool True  -> Just (VRight b, vs3)
              _           -> Nothing

     OptionT tx
      -> do (b, vs1) <- unmeltValue' vs0 BoolT
            (x, vs2) <- unmeltValue' vs1 tx
            case b of
              VBool False -> Just (VNone,   vs2)
              VBool True  -> Just (VSome x, vs2)
              _           -> Nothing
