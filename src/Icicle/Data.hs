{-# LANGUAGE NoImplicitPrelude #-}
module Icicle.Data (
    Entity (..)
  , Attribute (..)
  , Fact (..)
  , Fact' (..)
  , AsAt (..)
  , Value (..)
  , Struct (..)
  , List (..)
  , Date (..)
  , DateTime (..)
  , Encoding (..)
  , StructField (..)
  , StructFieldType (..)
  ) where

import           Data.Text

import           P


newtype Entity =
  Entity {
      getEntity     :: Text
    } deriving (Eq, Ord, Show)


newtype Attribute =
  Attribute {
      getAttribute  :: Text
    } deriving (Eq, Ord, Show)


data Fact =
  Fact {
      entity        :: Entity
    , attribute     :: Attribute
    , value         :: Value
    } deriving (Eq, Show)


data Fact' =
  Fact' {
      entity'       :: Entity
    , attribute'    :: Attribute
    , value'        :: Text
    } deriving (Eq, Show)


data AsAt a =
  AsAt {
      fact          :: a
    , time          :: DateTime
    } deriving (Eq, Show)


data Value =
    StringValue     Text
  | IntValue        Int
  | DoubleValue     Double
  | BooleanValue    Bool
  | DateValue       Date
  | StructValue     Struct
  | ListValue       List
  | Tombstone
  deriving (Eq, Show)


data Struct =
  Struct    [(Attribute, Value)]
  deriving (Eq, Show)


data List =
  List      [Value]
  deriving (Eq, Show)


data Date =
  Date {
      getDate       :: Text -- FIX complete, make these real...
    } deriving (Eq, Show)


data DateTime =
  DateTime {
      getDateTime   :: Text -- FIX complete, make these real...
    } deriving (Eq, Ord, Show)


data Encoding =
    StringEncoding
  | IntEncoding
  | DoubleEncoding
  | BooleanEncoding
  | DateEncoding
  | StructEncoding  [StructField]
  | ListEncoding    Encoding
  deriving (Eq, Show)


data StructField =
    StructField StructFieldType Attribute Encoding
  deriving (Eq, Show)


data StructFieldType =
    Mandatory
  | Optional
  deriving (Eq, Show)
