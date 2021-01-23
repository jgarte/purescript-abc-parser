-- | Handle any repeated sections when interpreting an ABC tune
-- | Repeats are optional and can take the form:
-- |    |: ABC :|
-- |    |:: ABC :|
-- |    |: ABC :: DEF :|
-- |    |: ABC |1 de :|2 fg |
-- |    |: ABC |1,3 de :|2,4 fg |
-- | the very first repeat start marker is optional and often absent
module Data.Abc.Repeats.Section
        ( initialRepeatState
        , indexBar
        , finalBar
        ) where

import Data.Abc (Volta(..))
import Data.Abc.Repeats.Types (Label(..), RepeatState, Section(..))
import Data.Abc.Repeats.Variant (initialVariantEndings, setVariantList, setVariantOf,
                                variantEndingOf)
import Data.Array (fromFoldable)
import Data.List (List(..), (:))
import Data.Maybe (Maybe(..), isJust)
import Data.Newtype (unwrap)
import Prelude ((==), (>), (<=), (&&), (-), ($), map, not)

-- | support extensible records for different possible melody forms in the rest
type IndexedBar rest = 
    { number :: Int
    , endRepeats :: Int
    , startRepeats :: Int
    , iteration :: Maybe Volta | rest }

-- | initial repeats i.e. no repeats yet.  intro is not used in MIDI production
initialRepeatState :: RepeatState
initialRepeatState =
  { current : nullSection, sections : Nil, intro : [] }

-- | index a bar by identifying any repeat markings and saving the marking against 
-- | the bar number
indexBar :: forall melody. IndexedBar melody
         -> RepeatState 
         -> RepeatState
indexBar bar r =
  case bar.iteration, bar.endRepeats, bar.startRepeats of
    -- |1 or |2 etc
    Just (Volta n), _ , _ ->    
      r { current = setVariantOf (toOffsetZero n) bar.number r.current}
    -- | 1,2 etc 
    Just (VoltaList vs), _ , _ ->
      let 
        vsArray = map toOffsetZero $ fromFoldable vs
      in
        r { current = setVariantList vsArray bar.number r.current}
    -- |: or :| or |
    Nothing,  ends,  starts ->    
      if (ends > 0 && starts > 0) then
        endAndStartSection bar.number true starts r
      else if (ends > 0 && starts <= 0) then
        endSection bar.number true r
      else if (ends <= 0 && starts > 0) then
        startSection bar.number starts r
      else 
        r

{-| accumulate any residual current state from the final bar in the tune -}
finalBar :: forall melody. IndexedBar melody
         -> RepeatState 
         -> RepeatState
finalBar bar r =
  let
    isRepeatEnd = bar.endRepeats > 0 
    repeatState = endSection bar.number isRepeatEnd r
  in
    if not (isDeadSection r.current) then
      accumulateSection bar.number 0 repeatState
    else
      repeatState

-- implementation

-- default sections i.e. no repeats yet
defaultSections :: RepeatState
defaultSections =
  { current : nullSection, sections : Nil, intro : [] }

-- accumulate the last section and start a new section  -}
startSection :: Int -> Int -> RepeatState -> RepeatState
startSection pos repeatStartCount r =
  -- a start implies an end of the last section
  endAndStartSection pos false repeatStartCount r

-- end the section.  If there is a first repeat, keep it open, else accumulate it
-- pos : the bar number marking the end of section
-- isRepeatEnd : True if invoked with a known Repeat End marker in the bar line
endSection :: Int -> Boolean -> RepeatState -> RepeatState
endSection pos isRepeatEnd r =
  if (hasFirstEnding r.current) then
    let
      current = setEndPos pos r.current
    in
      r { current = current }
  else
     endAndStartSection pos isRepeatEnd 0 r

-- end the current section, accumulate it and start a new section
endAndStartSection :: Int -> Boolean -> Int -> RepeatState -> RepeatState
endAndStartSection endPos isRepeatEnd repeatStartCount r =
  let
    -- cater for the situation where the ABC marks the first section of the tune as repeated solely by use
    -- of the End Repeat marker with no such explicit marker at the start of the section - it is implied as the tune start
    current :: Section
    current =
      if isRepeatEnd 
         && (unwrap r.current).start == Just 0 
         && (isUnrepeated r.current)  then
          setMissingRepeatCount r.current
      else
        r.current
    -- now set the end position from the bar number position
    current' = setEndPos endPos current
    -- set the new current into the state
    endState :: RepeatState
    endState = r { current = current' }
  in
    accumulateSection endPos repeatStartCount endState

-- accumulate the current section into the full score and re-initialise it
accumulateSection :: Int -> Int -> RepeatState -> RepeatState
accumulateSection pos repeatStartCount r =
  let
    newCurrent = newSection pos repeatStartCount
  in
    if not (isDeadSection r.current) then
      r { sections = r.current : r.sections, current = newCurrent}
    else
      r { current = newCurrent }

-- | volta repeat markers are wrt offset 1 - reduce to 0
toOffsetZero :: Int -> Int 
toOffsetZero i =
  if i <= 0 then 0 else i -1  


-- start a new section
newSection :: Int -> Int -> Section
newSection pos repeatCount = 
  Section
    { start : Just pos
    , variantEndings : initialVariantEndings
    , end : Just 0
    , repeatCount : repeatCount
    , label : OtherPart   -- not used here
    }

-- a 'null' section
nullSection :: Section
nullSection =
  newSection 0 0

-- return true if the section is devoid of any useful content
isDeadSection :: Section -> Boolean
isDeadSection s =
  s == nullSection

-- return true if the repeat count of a section is not set
isUnrepeated :: Section -> Boolean
isUnrepeated (Section s) =
  s.repeatCount == 0  

-- return true if the first (variant) ending is set
hasFirstEnding :: Section -> Boolean
hasFirstEnding s =
  isJust (variantEndingOf 0 s)

-- set the missing repeatedCount status of a section
setMissingRepeatCount :: Section -> Section
setMissingRepeatCount (Section s) =
  Section s { repeatCount = 1 }

-- set the end position of a section
setEndPos :: Int -> Section -> Section
setEndPos pos (Section s) =
  Section s { end = Just pos }

       
