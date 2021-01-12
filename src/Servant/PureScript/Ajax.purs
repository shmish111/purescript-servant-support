{--
  This file contains code copied from the purescript-affjax project from slamdata.
  It is therefore licensed under Apache License version 2.0.
--}

module Servant.PureScript.Ajax where

import Prelude

import Affjax (Request, Response, request, printError)
import Affjax as Affjax
import Affjax.RequestHeader (RequestHeader(..))
import Affjax.ResponseFormat as ResponseFormat
import Affjax.StatusCode (StatusCode(..))
import Control.Monad.Error.Class (class MonadError, throwError, try)
import Control.Monad.Except (runExcept, mapExcept)
import Data.Argonaut.Core (Json)
import Data.Array (find, length, zipWith, (..))
import Data.Bifunctor (lmap)
import Data.Either (Either(..))
import Data.Generic.Rep (class Generic)
import Data.List.NonEmpty (toList)
import Data.Maybe (Maybe(..), isJust)
import Data.MediaType.Common (applicationJSON)
import Data.Traversable (sequence)
import Effect.Aff (Aff, message)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Exception (Error)
import Foreign (F, Foreign, ForeignError(..), MultipleErrors, fail, readArray, readInt, readString, renderForeignError)
import Foreign.Generic (genericDecode)
import Foreign.Generic.Class (class GenericDecode, Options)
import Foreign.Generic.Internal (readObject)
import Foreign.JSON (parseJSON)
import Foreign.Object as O
import Servant.PureScript.JsUtils (unsafeToString)


newtype AjaxError
  = AjaxError
    { request     :: Request Unit
    , description :: ErrorDescription
    }

data ErrorDescription
  = DecodingError String
  | ConnectionError String
  | NotFound
  | ResponseError StatusCode String
  | ResponseFormatError String


makeAjaxError :: Request Unit -> ErrorDescription -> AjaxError
makeAjaxError req desc =
  AjaxError
    { request : req
    , description : desc
    }

runAjaxError :: AjaxError -> { request :: Request Unit, description :: ErrorDescription }
runAjaxError (AjaxError err) = err

errorToString :: AjaxError -> String
errorToString = unsafeToString

requestToString :: Request Json -> String
requestToString = unsafeToString

responseToString :: forall res. Response res -> String
responseToString = unsafeToString

class FromJSON a where
  fromJSON :: Options -> Foreign -> F a

instance intFromJSON :: FromJSON Int where
  fromJSON _ = readInt

else instance stringFromJSON :: FromJSON String where
  fromJSON _ = readString

else instance unitFromJSON :: FromJSON Unit where
  fromJSON _ _ = pure unit

else instance eitherFromJSON :: (FromJSON a, FromJSON b) => FromJSON (Either a b) where
  fromJSON opts f = do
    o <- readObject f
    let mr = O.lookup "Right" o
    let ml = O.lookup "Left" o
    case mr, ml of
      (Just a), _ -> Right <$> fromJSON opts a
      _, (Just b) -> Left <$> fromJSON opts b
      _, _ -> fail (ForeignError "Object is not an Either a b")

else instance arrayFromJSON :: FromJSON a => FromJSON (Array a) where
  fromJSON opts = readArray >=> readElements where
    readElements :: Array Foreign -> F (Array a)
    readElements arr = sequence (zipWith readElement (0 .. length arr) arr)

    readElement :: Int -> Foreign -> F a
    readElement i value = mapExcept (lmap (map (ErrorAtIndex i))) (fromJSON opts value)

else instance genericFromJSON :: (Generic a rep, GenericDecode rep) => FromJSON a where
  fromJSON = genericDecode

-- | Do an affjax call but report Aff exceptions in our own MonadError
ajax :: forall m res . MonadError AjaxError m => MonadAff m
        => (Foreign -> F res) -> Request Unit -> m (Response res)
ajax decoder req = do
  let headers = if hasContentType req.headers then req.headers else [ContentType applicationJSON] <> req.headers
  response <- tryRequest $ request $ req { responseFormat = ResponseFormat.string, headers = headers }
  decoded <- toDecodingError $ runExcept $ parseJSON response.body >>= decoder
  pure $ response { body = decoded }
  where
    toDecodingError :: forall a. Either MultipleErrors a -> m a
    toDecodingError r = case r of
        Left err -> throwError $ makeAjaxError req $ DecodingError (show (toList (map renderForeignError err)))
        Right v  -> pure v

    hasContentType :: Array RequestHeader -> Boolean
    hasContentType hs = isJust $ find isContentType hs

    isContentType :: RequestHeader -> Boolean
    isContentType (ContentType _) = true
    isContentType _ = false

    tryRequest :: Aff (Either Affjax.Error (Response String)) -> m (Response String)
    tryRequest action = do
       response <- liftAff $ try action
       toMonadError $ handleServerErrors response

    handleServerErrors :: Either Error (Either Affjax.Error (Response String)) -> Either AjaxError (Response String)
    handleServerErrors =
      lmap (makeAjaxError req) <<<
       case _ of
         Left jsError -> Left $ ConnectionError $ message jsError
         Right (Left affjaxError) -> Left $ ResponseFormatError $ printError affjaxError
         Right (Right (response@{status: status@(StatusCode statusCode), body})) ->
          if between 200 299 statusCode
          then pure response
          else Left $ if statusCode == 404
                      then NotFound
                      else ResponseError status body

toMonadError :: forall m e a. MonadError e m => Either e a -> m a
toMonadError (Left err) = throwError err
toMonadError (Right value) = pure value
