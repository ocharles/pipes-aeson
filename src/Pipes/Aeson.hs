{-# LANGUAGE RankNTypes #-}

-- | This module allows you to encode and decode JSON values flowing downstream
-- through Pipes streams.
--
-- This module builds on top of the @aeson@, @pipes@ and @pipes-parse@
-- libraries, and assumes you know how to use them.

module Pipes.Aeson
  ( -- * Encoding
    encode
    -- * Decoding
    -- $decoding
  , decode
  , decodeMany
    -- * Types
  , I.DecodingError(..)
  ) where

import           Pipes
import qualified Pipes.Aeson.Internal             as I
import qualified Pipes.Aeson.Unsafe               as U
import qualified Pipes.Attoparsec                 as PA
import qualified Control.Monad.Trans.State.Strict as S
import qualified Data.Aeson                       as Ae
import qualified Data.ByteString.Char8            as B

--------------------------------------------------------------------------------

-- | Encode an 'Ae.Array' or 'Ae.Object' as JSON and send it downstream,
-- possibly in more than one 'B.ByteString' chunk.
--
-- /Note:/ The JSON RFC-4627 standard only allows arrays or objects as top-level
-- entities, which is why this function restricts its input to them. If you
-- prefer to ignore the standard and encode any 'Ae.Value', then use 'U.encode'.
encode :: Monad m => Either Ae.Object Ae.Array -> Producer B.ByteString m ()
encode = either U.encode U.encode
{-# INLINABLE encode #-}

--------------------------------------------------------------------------------
-- $decoding
--
-- Decoding JSON as a Haskell value in involves two different steps:
--
-- * Parsing a raw JSON 'B.ByteString' into an 'Ae.Object' or an 'Ae.Array'.
--
-- * Converting the obtained 'Ae.Object' or 'Ae.Array' to the desired
-- 'Ae.FromJSON' instance.
--
-- Any of those steps can fail, in which case a 'I.DecodingError' will report
-- the precise error and at which the step it appened.


-- | Decodes an 'Ae.Object' or 'Ae.Array' JSON value from the underlying state.
--
-- /Do not/ use this function if the underlying 'Producer' has leading empty
-- chunks or whitespace, otherwise you may get unexpected parsing errors. That
-- is, check that 'Pipes.ByteString.isEndOfBytes' returns 'True' before using
-- this function.
--
-- /Note:/ The JSON RFC-4627 standard only allows arrays or objects as top-level
-- entities, which is why this 'Producer' restricts its output to them. If you
-- prefer to ignore the standard and decode any 'Ae.Value', then use 'U.decode'.
decode
  :: (Monad m, Ae.FromJSON b)
  => S.StateT (Producer B.ByteString m r) m (Either I.DecodingError (Int, b))
decode = do
    ev <- PA.parse Ae.json'
    return $ do
      case ev of
        Left  e        -> Left (I.ParserError e)
        Right (len, v) -> do
          case Ae.fromJSON v of
            Ae.Error e   -> Left (I.ValueError e)
            Ae.Success b -> Right (len, b)
{-# INLINABLE decode #-}

-- | Continuously 'decode' the JSON output from the given 'Producer', sending
-- downstream pairs of each successfully decoded entity together with the number
-- of bytes consumed in order to produce it.
--
-- This 'Producer' runs until it either runs out of input, in which case it
-- returns @'Right' ()@, or until a decoding failure occurs, in which case
-- it returns a 'Left' providing a 'I.DecodingError' and a 'Producer' with any
-- leftovers.
decodeMany
  :: (Monad m, Ae.FromJSON b)
  => Producer B.ByteString m r  -- ^Producer from which to draw JSON.
  -> Producer (Int, b) m
              (Either (I.DecodingError, Producer B.ByteString m r) ())
decodeMany = I.consecutively decode
{-# INLINABLE decodeMany #-}
