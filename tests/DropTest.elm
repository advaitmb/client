module DropTest exposing (dropsOntoAnotherParent, dropsWithinOneParent, dropsWithNowhereToGo, dropsIntoACard)

{-| Where a dragged card lands (ADR-0001 seam 9).

`<gw-tree>` reports a native drag-drop as `{dragged, target, where}`; the
placement that answers it is `Doc.TreeStructure.dropPlacement`, a pure function
of (dragged card, drop region, tree), and `Page.Doc` only carries it out. The
decision is extracted because `Page.Doc.Msg` is opaque and its `update` returns
`Cmd`s no test can inspect.

Every index here is an index into the children of a parent *after* the dragged
card has been pruned out of it, because that is exactly what `Mov` does with it
(prune, then insert) and what `Doc.Data.placeCard` does with the position it
turns into (its sibling list excludes the card being moved). Reading the index
off the tree as it appears on screen -- the dragged card still counted -- put
every same-parent downward drop one slot too far (CODE_REVIEW.md E7).

-}

import Doc.TreeStructure as TreeStructure exposing (dropPlacement)
import Doc.TreeUtils exposing (getChildren, getTree)
import Expect
import Test exposing (Test, describe, test)
import Types exposing (Children(..), DropId(..), Tree)


{-| A document with three top-level cards, the middle one having two children:

    a
    b -- b1, b2
    c

-}
doc : Tree
doc =
    node "0"
        [ node "a" []
        , node "b" [ node "b1" [], node "b2" [] ]
        , node "c" []
        ]


node : String -> List Tree -> Tree
node id children =
    { id = id, content = id, children = Children children }


{-| The ids under `parentId`, in order, after carrying the drop out: the same
`Mov` `Page.Doc` builds from a placement.
-}
childIdsAfterDrop : String -> DropId -> String -> List String
childIdsAfterDrop draggedId dropId parentId =
    case ( getTree draggedId doc, dropPlacement draggedId dropId doc ) of
        ( Just dragged, Just placement ) ->
            TreeStructure.apply [ TreeStructure.Mov dragged placement.parentId placement.index ] doc
                |> getTree parentId
                |> Maybe.map (getChildren >> List.map .id)
                |> Maybe.withDefault [ "no such parent" ]

        _ ->
            [ "no move" ]


dropsWithinOneParent : Test
dropsWithinOneParent =
    describe "A drop among the dragged card's own siblings"
        [ test "below the next sibling lands between the two" <|
            \_ ->
                childIdsAfterDrop "a" (Below "b") "0"
                    |> Expect.equal [ "b", "a", "c" ]
        , test "above a later sibling lands directly above it" <|
            \_ ->
                childIdsAfterDrop "a" (Above "c") "0"
                    |> Expect.equal [ "b", "a", "c" ]
        , test "below the last sibling lands last" <|
            \_ ->
                childIdsAfterDrop "a" (Below "c") "0"
                    |> Expect.equal [ "b", "c", "a" ]
        , test "below an earlier sibling lands directly below it" <|
            \_ ->
                childIdsAfterDrop "c" (Below "a") "0"
                    |> Expect.equal [ "a", "c", "b" ]
        , test "above the first sibling lands first" <|
            \_ ->
                childIdsAfterDrop "c" (Above "a") "0"
                    |> Expect.equal [ "c", "a", "b" ]
        , test "the index counts the siblings the card leaves behind" <|
            \_ ->
                dropPlacement "a" (Below "b") doc
                    |> Expect.equal (Just { parentId = "0", index = 1 })
        ]


dropsOntoAnotherParent : Test
dropsOntoAnotherParent =
    describe "A drop onto a card under another parent"
        [ test "below it lands directly below it" <|
            \_ ->
                childIdsAfterDrop "a" (Below "b1") "b"
                    |> Expect.equal [ "b1", "a", "b2" ]
        , test "above it lands directly above it" <|
            \_ ->
                childIdsAfterDrop "c" (Above "b2") "b"
                    |> Expect.equal [ "b1", "c", "b2" ]
        , test "leaves the parent it came from" <|
            \_ ->
                childIdsAfterDrop "a" (Below "b1") "0"
                    |> Expect.equal [ "b", "c" ]
        ]


dropsIntoACard : Test
dropsIntoACard =
    describe "A drop into a card"
        [ test "appends it to that card's children" <|
            \_ ->
                childIdsAfterDrop "a" (Into "b") "b"
                    |> Expect.equal [ "b1", "b2", "a" ]
        , test "makes a childless card a parent" <|
            \_ ->
                childIdsAfterDrop "a" (Into "c") "c"
                    |> Expect.equal [ "a" ]
        ]


dropsWithNowhereToGo : Test
dropsWithNowhereToGo =
    describe "A drop that names no place the card can go"
        [ -- The card and its subtree are pruned before being re-inserted, so a
          -- target inside that subtree is not in the tree the card is inserted
          -- into: `insertSubtree` would find no such parent and drop every card
          -- in the subtree on the floor.
          test "into its own child is no move" <|
            \_ ->
                dropPlacement "b" (Into "b1") doc
                    |> Expect.equal Nothing
        , test "below its own child is no move" <|
            \_ ->
                dropPlacement "b" (Below "b1") doc
                    |> Expect.equal Nothing
        , test "onto itself is no move" <|
            \_ ->
                dropPlacement "b" (Above "b") doc
                    |> Expect.equal Nothing
        , test "onto a card that is not in the tree is no move" <|
            \_ ->
                dropPlacement "a" (Below "gone") doc
                    |> Expect.equal Nothing
        , test "into a card that is not in the tree is no move" <|
            \_ ->
                dropPlacement "a" (Into "gone") doc
                    |> Expect.equal Nothing
        ]
