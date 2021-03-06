{-# OPTIONS_HADDOCK show-extensions #-}

{-# LANGUAGE Safe #-}

{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Data.QuadTree.Internal
Description : Internals for the Data.QuadTree library.
Copyright   : (c) Ashley Moni, 2015
License     : BSD3
Maintainer  : Ashley Moni <ashley.moni1@gmail.com>
Stability   : Stable

The QuadTree.Internals library is a separately encapsulated subset of
the QuadTree library, strictly for the purpose of exposing inner
structure and functions to the testing suites.
|-}

module Data.QuadTree.Internal where

import Control.Lens.Type (Lens')
import Control.Lens.Setter (over, set)
import Control.Lens.Getter (view)

import Data.List (find, sortBy)
import Data.Function (on)
import Data.Composition ((.:))

---- Structures:

-- |Tuple corresponds to (X, Y) co-ordinates.

type Location = (Int, Int)

-- |The eponymous data type.
--
-- 'QuadTree' is itself a wrapper around an internal tree structure
-- along with spatial metadata about the boundaries and depth of the
-- 2D area it maps to.

data QuadTree a = Wrapper { wrappedTree :: Quadrant a
                          , treeLength :: Int
                          , treeWidth  :: Int
                          , treeDepth :: Int }
  deriving (Show, Read, Eq)

-- |'QuadTree's are 'Functor's, and their elements can be fmapped over.
instance Functor QuadTree where
  fmap fn = onQuads $ fmap fn

-- |'QuadTree's are 'Foldable', though the traversal path is a complex
-- recursive enumeration of internal 'Quadrant's. Don't use folds that aren't
-- ordering agnostic.
instance Foldable QuadTree where
  foldr = foldTree

-- Quadrants:

-- |The internal data structure of a 'QuadTree'.
--
-- Each 'Quadrant' consists of either a terminating Leaf node, or
-- four further 'Quadrant's.

data Quadrant a = Leaf a
                | Node (Quadrant a)
                       (Quadrant a)
                       (Quadrant a)
                       (Quadrant a)
  deriving (Show, Read, Eq)

-- |'Quadrant's are 'Functor's. -- You can fmap all their recursive leaf node.
instance Functor Quadrant where
  fmap fn (Leaf x)       = Leaf (fn x)
  fmap fn (Node a b c d) = Node (fmap fn a)
                                (fmap fn b)
                                (fmap fn c)
                                (fmap fn d)

---- Quadrant lenses:

-- |Lens for the top left 'Quadrant' of a node.
_a :: forall a. Eq a => Lens' (Quadrant a) (Quadrant a)
_a f (Node a b c d) = fmap (\x -> fuse $ Node x b c d) (f a)
_a f leaf           = fmap embed (f leaf)
  where embed :: Quadrant a -> Quadrant a
        embed x | x == leaf = leaf
                | otherwise = Node x leaf leaf leaf

-- |Lens for the top right 'Quadrant' of a node.
_b :: forall a. Eq a => Lens' (Quadrant a) (Quadrant a)
_b f (Node a b c d) = fmap (\x -> fuse $ Node a x c d) (f b)
_b f leaf           = fmap embed (f leaf)
  where embed :: Quadrant a -> Quadrant a
        embed x | x == leaf = leaf
                | otherwise = Node leaf x leaf leaf

-- |Lens for the bottom left 'Quadrant' of a node.
_c :: forall a. Eq a => Lens' (Quadrant a) (Quadrant a)
_c f (Node a b c d) = fmap (\x -> fuse $ Node a b x d) (f c)
_c f leaf           = fmap embed (f leaf)
  where embed :: Quadrant a -> Quadrant a
        embed x | x == leaf = leaf
                | otherwise = Node leaf leaf x leaf

-- |Lens for the bottom right 'Quadrant' of a node.
_d :: forall a. Eq a => Lens' (Quadrant a) (Quadrant a)
_d f (Node a b c d) = fmap (fuse . Node a b c) (f d)
_d f leaf           = fmap embed (f leaf)
  where embed :: Quadrant a -> Quadrant a
        embed x | x == leaf = leaf
                | otherwise = Node leaf leaf leaf x

-- |Lens for a terminate leaf value of a node.
_leaf :: Lens' (Quadrant a) a
_leaf f (Leaf leaf) = Leaf <$> f leaf
_leaf _ _           = error "Wrapped tree is deeper than cached tree depth."

-- |Lens to zoom into the internal data structure of a 'QuadTree',
-- lensing past the metadata to reveal the 'Quadrant' inside.
_wrappedTree :: Lens' (QuadTree a) (Quadrant a)
_wrappedTree f qt = (\x -> qt {wrappedTree = x}) <$> f (wrappedTree qt)

-- |Unsafe sanity test lens that makes sure a given location index exists
-- within the relevant 'QuadTree'.
verifyLocation :: Location -> Lens' (QuadTree a) (QuadTree a)
verifyLocation index f qt
  | index `outOfBounds` qt = error "Location index out of QuadTree bounds."
  | otherwise              = f qt

---- Index access:

-- |Lens for accessing and manipulating data at a specific
-- location.
atLocation :: forall a. Eq a => Location -> Lens' (QuadTree a) a
atLocation index fn qt = (verifyLocation index . _wrappedTree .
                          go (offsetIndex qt index) (treeDepth qt)) fn qt
  where
    go :: Eq a => Location -> Int -> Lens' (Quadrant a) a
    go _     0 = _leaf
    go (x,y) n | y < mid   = if x < mid then _a . recurse
                                        else _b . recurse
               | otherwise = if x < mid then _c . recurse
                                        else _d . recurse
      where recurse = go (x `mod` mid, y `mod` mid) (n - 1)
            mid = 2 ^ (n - 1)

-- |Getter for the value at a given location for a 'QuadTree'.
getLocation :: Eq a => Location -> QuadTree a -> a
getLocation = view . atLocation

-- |Setter for the value at a given location for a 'QuadTree'.
--
-- This automatically compresses the 'QuadTree' nodes if possible with
-- the new value.
setLocation :: Eq a => Location -> a -> QuadTree a -> QuadTree a
setLocation = set . atLocation

-- |Modifies value at a given location for a 'QuadTree'.
--
-- This automatically compresses the 'QuadTree' nodes if possible with
-- the new value.
mapLocation :: Eq a => Location -> (a -> a) -> QuadTree a -> QuadTree a
mapLocation = over . atLocation

---- Helpers:

-- |Checks if a 'Location' is outside the boundaries of a 'QuadTree'.
outOfBounds :: Location -> QuadTree a -> Bool
outOfBounds (x,y) tree = x < 0 || y < 0
                         || x >= treeLength tree
                         || y >= treeWidth  tree

-- |Dimensions of a 'QuadTree', as an Int pair.
treeDimensions :: QuadTree a
               -> (Int, Int) -- ^ (Length, Width)
treeDimensions tree = (treeLength tree, treeWidth tree)

-- |Add offsets to a location index for the purpose of querying
-- the 'QuadTree' 's true reference frame.
offsetIndex :: QuadTree a -> Location -> Location
offsetIndex tree (x,y) = (x + xOffset, y + yOffset)
  where (xOffset, yOffset) = offsets tree

-- |Offsets added to a 'QuadTree' 's true reference frame
-- to reference elements in the centralized width and height.
offsets :: QuadTree a -> (Int, Int)
offsets tree = (xOffset, yOffset)
  where xOffset = (dimension - treeLength tree) `div` 2
        yOffset = (dimension - treeWidth  tree) `div` 2
        dimension = 2 ^ treeDepth tree

-- |Merge 'Quadrant' into a leaf node if possible.
fuse :: Eq a => Quadrant a -> Quadrant a
fuse (Node (Leaf a) (Leaf b) (Leaf c) (Leaf d))
  | allEqual [a,b,c,d] = Leaf a
fuse oldNode            = oldNode

-- |Test if all elements in a list are equal.
allEqual :: Eq a => [a] -> Bool
allEqual = and . (zipWith (==) <*> tail)

---- Functor:

-- |Apply a function to a 'QuadTree's internal 'Quadrant'.
onQuads :: (Quadrant a -> Quadrant b) -> QuadTree a -> QuadTree b
onQuads fn tree = tree {wrappedTree = fn (wrappedTree tree)}

-- |Cleanup function for use after any 'Control.Monad.fmap'.
--
-- When elements of a 'QuadTree' are modified by 'setLocation' (or 
-- the 'atLocation' lens), it automatically compresses identical
-- adjacent nodes into larger ones. This keeps the 'QuadTree' from
-- bloating over constant use.
--
-- 'Control.Monad.fmap' does not do this. If you wish to treat the
-- 'QuadTree' as a 'Control.Monad.Functor', you should compose this
-- function after to collapse it down to its minimum size.
--
-- Example:
-- @
-- 'fuseTree' $ 'Control.Monad.fmap' fn tree
-- @
-- This particular example is reified in the function below.

fuseTree :: Eq a => QuadTree a -> QuadTree a
fuseTree = onQuads fuseQuads
  where fuseQuads :: Eq a => Quadrant a -> Quadrant a
        fuseQuads (Node a b c d) = fuse $ Node (fuseQuads a)
                                        (fuseQuads b)
                                        (fuseQuads c)
                                        (fuseQuads d)
        fuseQuads leaf           = leaf

-- |tmap is simply 'Control.Monad.fmap' with 'fuseTree' applied after.
--
-- prop> tmap fn tree == fuseTree $ fmap fn tree
tmap :: Eq b => (a -> b) -> QuadTree a -> QuadTree b
tmap = fuseTree .: fmap

---- Foldable:

-- |Rectangular area, represented by a tuple of four Ints.
--
-- They correspond to (X floor, Y floor, X ceiling, Y ceiling).
--
-- The co-ordinates are inclusive of all the rows and columns in all
-- four Ints.
--
-- prop> regionArea (x, y, x, y) == 1

type Region = (Int, Int, Int, Int)

-- |Each 'Tile' is a tuple of an element from a 'QuadTree' and the
-- 'Region' it subtends.

type Tile a = (a, Region)

-- |Foldr elements within a 'QuadTree', by first decomposing it into
-- 'Tile's and then decomposing those into lists of identical data values.

foldTree :: (a -> b -> b) -> b -> QuadTree a -> b
foldTree fn z = foldr fn z . expand . tile

-- |Takes a list of 'Tile's and then decomposes them into a list of
-- all their elements, properly weighted by 'Tile' size.

expand :: [Tile a] -> [a]
expand = concatMap decompose
  where decompose :: Tile a -> [a]
        decompose (a, r) = replicate (regionArea r) a

-- |Returns a list of 'Tile's. The block equivalent of
-- 'Data.Foldable.toList'.

tile :: QuadTree a -> [Tile a]
tile = foldTiles (:) []

-- |Decomposes a 'QuadTree' into its constituent 'Tile's, before
-- folding a 'Tile' consuming function over all of them.

foldTiles :: forall a b. (Tile a -> b -> b) -> b -> QuadTree a -> b
foldTiles fn z tree = go (treeRegion tree) (wrappedTree tree) z
  where go :: Region -> Quadrant a -> b -> b
        go r (Leaf a) = fn (a, normalizedIntersection)
          where normalizedIntersection =
                  (interXl - xOffset, interYt - yOffset,
                   interXr - xOffset, interYb - yOffset)
                (interXl, interYt, interXr, interYb) = 
                  treeIntersection r
        go (xl, yt, xr, yb) (Node a b c d) =
          go (xl,       yt,       midx, midy) a .
          go (midx + 1, yt,       xr,   midy) b .
          go (xl,       midy + 1, midx, yb)   c .
          go (midx + 1, midy + 1, xr,   yb)   d
          where midx = (xr + xl) `div` 2
                midy = (yt + yb) `div` 2

        (xOffset, yOffset) = offsets tree
        treeIntersection   = regionIntersection $ boundaries tree

-- |The region denoting an entire 'QuadTree'.
treeRegion :: QuadTree a -> Region
treeRegion tree = (0, 0, limit, limit)
  where limit = (2 ^ treeDepth tree) - 1

-- |The boundary 'Region' of the internal 'QuadTree' 's true reference frame.
boundaries :: QuadTree a -> Region
boundaries tree = (left, top, right, bottom)
  where (left,  top)    = offsetIndex tree (0,0)
        (right, bottom) = offsetIndex tree (treeLength tree - 1,
                                            treeWidth  tree - 1)

-- |'Region' that's an intersection between two othe 'Region's.
regionIntersection :: Region -> Region -> Region
regionIntersection (xl , yt , xr , yb )
                   (xl', yt', xr', yb') =
  (max xl xl', max yt yt',
   min xr xr', min yb yb')

-- |Simple helper function that lets you calculate the area of a
-- 'Region', usually for 'Data.List.replicate' purposes.

regionArea :: Region -> Int
regionArea (xl,yt,xr,yb) = (xr + 1 - xl) * (yb + 1 - yt)

-- |Does the region contain this location?

inRegion :: Location -> Region -> Bool
inRegion (x,y) (xl,yt,xr,yb) = xl <= x && x <= xr &&
                               yt <= y && y <= yb

---- Foldable extras:

-- |'Data.List.filter's a list of the 'QuadTree' 's elements.

filterTree :: (a -> Bool) -> QuadTree a -> [a]
filterTree fn = expand . filterTiles fn . tile

-- |'Data.List.sortBy's a list of the 'QuadTree' 's elements.

sortTreeBy :: (a -> a -> Ordering) -> QuadTree a -> [a]
sortTreeBy fn = expand . sortTilesBy fn . tile

-- |'Data.List.filter's a list of the 'Tile's of a 'QuadTree'.

filterTiles :: (a -> Bool) -> [Tile a] -> [Tile a]
filterTiles _  [] = []
filterTiles fn ((a,r) : rs)
  | fn a      = (a,r) : filterTiles fn rs
  | otherwise =         filterTiles fn rs

-- |'Data.List.sortBy's a list of the 'Tile's of a 'QuadTree'.

sortTilesBy :: (a -> a -> Ordering) -> [Tile a] -> [Tile a]
sortTilesBy fn = sortBy (fn `on` fst)

---- Constructor:

-- |Constructor that generates a 'QuadTree' of the given dimensions,
-- with all cells filled with a default value.

makeTree :: (Int, Int) -- ^ (Length, Width)
         -> a          -- ^ Initial element to fill
         -> QuadTree a
makeTree (x,y) a
  | x <= 0 || y <= 0 = error "Invalid dimensions for tree."
  | otherwise = Wrapper { wrappedTree = Leaf a
                        , treeLength = x
                        , treeWidth  = y
                        , treeDepth = smallestDepth (x,y) }

-- |Find the smallest tree depth that would encompass a given width and height.
smallestDepth :: (Int, Int) -> Int
smallestDepth (x,y) = depth
  where (depth, _)         = smallestPower
        Just smallestPower = find bigEnough powersZip
        bigEnough (_, e)   = e >= max x y
        powersZip          = zip [0..] $ iterate (* 2) 1

---- Sample Printers:

-- |Generates a newline delimited string representing a 'QuadTree' as
-- a 2D block of characters.
--
-- Note that despite the word 'show' in the function name, this does
-- not 'Text.show' the 'QuadTree'. It pretty prints it. The name
-- is simply a mnemonic for its @'QuadTree' -> String@ behaviour.

showTree :: Eq a => (a -> Char) -- ^ Function to generate characters for each
                                -- 'QuadTree' element.
                 -> QuadTree a -> String
showTree printer tree = breakString (treeLength tree) string
  where string   = map printer grid
        grid = [getLocation (x,y) tree |
                y <- [0 .. treeWidth  tree - 1],
                x <- [0 .. treeLength tree - 1]]
        breakString :: Int -> String -> String
        breakString _ [] = []
        breakString n xs = a ++ "\n" ++ breakString n b
          where (a,b) = splitAt n xs

-- |As 'showTree' above, but also prints it.

printTree :: Eq a => (a -> Char) -- ^ Function to generate characters for each
                                 -- 'QuadTree' element.
                  -> QuadTree a -> IO ()
printTree = putStr .: showTree
