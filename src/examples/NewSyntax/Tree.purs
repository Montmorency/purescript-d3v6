module NewSyntax.Tree (
    Model, TreeConfig -- TODO move to Base
  , MyModel, ModelData, Tree(..), TreeJson -- NB no constructor
  , chart
  , readModelFromFileContents -- read the tree structure
  , makeModel -- post process tree structure such that it can be used to render using chart
) where

import D3.Base

import Affjax (Error)
import Data.Either (Either(..))
import Data.Tuple (Tuple(..))
import Debug.Trace (spy)
import Math (pi)
import Prelude (negate, show, ($), (*), (-), (/), (<), (<>), (==), (>=))
import Unsafe.Coerce (unsafeCoerce)

-- this stuff belongs eventually in the d3 base
data Tree a = Node a (Array (Tree a))
type TreeConfig a = {
    size       :: Array Number
  , separation :: Datum -> Datum -> Int
}

radialTreeConfig :: forall a. Number -> TreeConfig a
radialTreeConfig width = 
  { size: [2.0 * pi, width / 2.0]
  , separation: radialSeparationJS
  }

data Model a = Model {
      json :: TreeJson
    , d3Tree :: D3Tree
    , config :: TreeConfig a
}

foreign import radialSeparationJS :: Datum -> Datum -> Int

-- this is the INITIAL data that is in the hierarchy before we embed it in the D3 structures
-- if we have a Model ModelData then we are guaranteed to be able to coerce the inner "data"
-- field to this ModelData type
type ModelData = { name :: String }
-- this is the model that this particular "chart" / simulation uses
type MyModel = Model ModelData

-- this is an opaque type behind which hides the data type of the Purescript tree that was converted
foreign import data RecursiveD3TreeNode :: Type
-- this is the Purescript Tree after processing in JS to remove empty child fields from leaves etc
-- need to ensure that this structure is encapsulated in libraries (ie by moving this code)
foreign import data D3Tree :: Type
foreign import data D3Hierarchical :: Type
foreign import data TreeJson :: Type
type D3TreeNode = {
    "data"   :: ModelData -- guaranteed coercible to the `a` of the `Model a`
  , x        :: Number
  , y        :: Number
  , value    :: String
  , depth    :: Number
  , height   :: Number
-- these next too are guaranteed coercible to the same type, ie D3TreeNode
-- BUT ONLY IF the D3Tree is a successful conversion using d3Hierarchy
-- TODO code out exceptions
  , parent   :: RecursiveD3TreeNode -- this won't be present in the root node
  , children :: Array RecursiveD3TreeNode -- this won't be present in leaf nodes
}

-- do the decode on the Purescript side unless files are ginormous, this is just for prototyping
foreign import readJSONJS :: String -> TreeJson -- TODO no error handling at all here RN
foreign import d3Hierarchy :: TreeJson -> D3Hierarchical
foreign import d3InitTree :: forall a. TreeConfig a -> D3Hierarchical -> D3Tree 
foreign import hasChildren :: Datum -> Boolean

makeModel :: Number -> TreeJson -> Model String
makeModel width json = Model { json, d3Tree, config }
  where
    config           = radialTreeConfig width
    hierarchicalData = d3Hierarchy json
    d3Tree           = d3InitTree config hierarchicalData
  
readModelFromFileContents :: forall r. Tuple Number Number -> Either Error { body ∷ String | r } -> Either Error (Model String)
readModelFromFileContents (Tuple width _) (Right { body } ) = Right $ makeModel width (readJSONJS body)
readModelFromFileContents _               (Left error)      = Left error

-- we give the chart our Model type but behind the scenes it is mutated by D3 and additionally
-- which projection of the "Model" is active in each Join varies so we can't have both strong
-- static type representations AND lightweight syntax with JS compatible lambdas
d3TreeNode :: Datum -> D3TreeNode
d3TreeNode = unsafeCoerce

chart :: Tuple Number Number -> Selection (Model String)
chart (Tuple width height) = 
  let
    origin = { x: -width / 2.0, y: -height / 2.0 }
    -- three little transform functions to build up the transforms on nodes and labels
    rotate x = show $ (x * 180.0 / pi - 90.0)
    rotateCommon d = "rotate(" <> rotate (d3TreeNode d).x <> ")"
    rotateText2 d = "rotate(" <> if (d3TreeNode d).x >= pi 
                                 then "180" <> ")" 
                                 else "0" <> ")"
    -- same translation for both text and node
    translate d = "translate(" <> show (d3TreeNode d).y <> ",0)"
  in
    initialSelect "div#tree" "treeLayout" noAttrs $ [
      appendNamed "svg" Svg [ viewBox origin.x origin.y width height ] [
        append Group noAttrs 
          [ join Path modelLinks
            (appendNamed "link" Path [ strokeWidth 1.5
                                     , strokeColor "#555"
                                     , strokeOpacity 0.4
                                     , fill "none"
                                     , radialLink (\d -> (d3TreeNode d).x) (\d -> (d3TreeNode d).y) ] noChildren)
            noUpdate noExit ]
          
        , append Group noAttrs
          [ join Circle modelDescendants
            (appendNamed "node" Circle [ radius 2.5
                                       , fill_D (\d -> if hasChildren d then "#555" else "#999")
                                       , transform [ rotateCommon, translate ] ] noChildren)
            noUpdate noExit ]
        , append Group [ fontFamily "sans-serif"
                       , fontSize 10.0
                       , strokeLineJoin Round
                       , strokeWidth 3.0]
          [ join Text modelDescendants
            (appendNamed "text" Text [ transform [ rotateCommon, translate, rotateText2]
                                     , StaticString "dy" "0.31em"
                                     , NumberAttr "x" labelOffset
                                     , StringAttr "text-anchor" textOffset
                                     , TextAttr (\d -> (d3TreeNode d).data.name) 
                                     -- TODO add clone step later 
                                     ] noChildren)
            noUpdate noExit ]
        ]
    ]




labelOffset :: Datum -> Number
labelOffset d =
  if ((d3TreeNode d).x < pi) == (hasChildren d)
  then 6.0
  else -6.0

textOffset :: Datum -> String
textOffset d =
  if ((d3TreeNode d).x < pi) == (hasChildren d)
  then "start"
  else "end"

-- Projection functions to get subModels out of the Model for sub-selections
foreign import d3HierarchyLinks :: D3Tree -> SubModel
foreign import d3HierarchyDescendants :: D3Tree -> SubModel

modelLinks :: forall a. Model a -> SubModel
modelLinks (Model model) = d3HierarchyLinks model.d3Tree

modelDescendants :: forall a. Model a -> SubModel
modelDescendants (Model model) = d3HierarchyDescendants model.d3Tree

