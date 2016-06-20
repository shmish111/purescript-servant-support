{--
  This file contains code copied from the purescript-affjax project from slamdata.
  It is therefore licensed under Apache License version 2.0.
--}
module Servant.PureScript.Settings where


import Prelude

import Data.Argonaut.Core (Json())
import Data.Argonaut.Generic.Aeson as Aeson
import Data.Argonaut.Generic.Util (stripModulePath)
import Data.Generic (class Generic, GenericSpine(SArray, SChar, SString, SNumber, SInt, SBoolean, SRecord, SProd, SUnit), toSpine)
import Data.Either (Either)
import Data.Array (null)
import Data.String (joinWith)


-- | WARNING: encodeJson, decodeJson, toURLPiece: currently ignored due to compiler bug:
--   https://github.com/purescript/purescript/issues/1957
newtype SPSettings_ params = SPSettings_ {
    encodeJson :: forall a. Generic a => a -> Json -- Currently not used (does not work - compiler bug: )
  , decodeJson :: forall a. Generic a => Json -> Either String a
  , toURLPiece :: forall a. Generic a => a -> URLPiece
  , params :: params
  }

type URLPiece = String

gDefaultToURLPiece :: forall a. Generic a => a -> URLPiece
gDefaultToURLPiece = gToURLPiece <<< toSpine
  where
    gToURLPiece :: GenericSpine -> String
    gToURLPiece (SProd s arr) = genericShowPrec 0 $ SProd (stripModulePath s) arr
    gToURLPiece s = genericShowPrec 0 s


defaultSettings :: forall params. params -> SPSettings_ params
defaultSettings params = SPSettings_ {
    encodeJson : Aeson.encodeJson
  , decodeJson : Aeson.decodeJson
  , toURLPiece : gDefaultToURLPiece
  , params : params
}


genericShowPrec :: Int -> GenericSpine -> String
genericShowPrec d (SProd s arr) =
    if null arr
    then s
    else showParen (d > 10) $ s <> " " <> joinWith " " (map (\x -> genericShowPrec 11 (x unit)) arr)
  where showParen false x = x
        showParen true  x = "(" <> x <> ")"

genericShowPrec d (SRecord xs) = "{" <> joinWith ", " (map (\x -> x.recLabel <> ": " <> genericShowPrec 0 (x.recValue unit)) xs) <> "}"
genericShowPrec d (SBoolean x) = show x
genericShowPrec d (SInt x)     = show x
genericShowPrec d (SNumber x)  = show x
genericShowPrec d (SString x)  = show x
genericShowPrec d (SChar x)    = show x
genericShowPrec d (SArray xs)  = "[" <> joinWith ", "  (map (\x -> genericShowPrec 0 (x unit)) xs) <> "]"
genericShowPrec d SUnit        = show unit
