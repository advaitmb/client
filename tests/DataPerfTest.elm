module DataPerfTest exposing (suite)

{-| `Doc.Data` at the size the data layer is meant to survive: a synthetic
five-thousand-card document, put through the paths every save and every
card-rows echo runs (CODE_REVIEW.md P1, ticket 25).

Each of those paths used to scan the whole version log once per card, so the
work grew with the square of the document. These are ordinary assertions, and
the cost is what they carry besides: they take about a fifth of a second here,
where the same fixture against the pre-index code took three seconds at 3,500
cards and could not finish at all at five thousand (see `documentSize`).

`materializes the same tree as a filter-per-node walk` is the one that pins the
refactor rather than its cost: the tree built through the children-by-parent
index is compared against a naive walk that filters the whole card list for
every node -- the algorithm the index replaced, spelled out here.

-}

import Doc.Data as Data
import Expect
import Json.Decode as Dec
import Json.Encode as Enc
import Outgoing
import Test exposing (Test, describe, test)
import Types exposing (CardTreeOp(..), Children(..), Tree)
import UpdatedAt exposing (UpdatedAt)


{-| Cards per parent in the synthetic document below.
-}
fanout : Int
fanout =
    10


{-| A synthetic document of `count` cards: a ten-ary tree, one version row per
card, in id order.

Card `i` hangs off card `i // fanout - 1`, so the first ten cards are roots and
every card ends up with ten children -- a shape with both breadth (columns as
wide as the fanout) and depth (five levels at five thousand cards), which is
what the cost of a tree walk rides on.

-}
docRows : Bool -> Int -> List (Data.Card_tests_only UpdatedAt)
docRows synced count =
    List.range 0 (count - 1)
        |> List.map
            (\i ->
                { id = cardId i
                , treeId = "tree1"
                , content = "Card " ++ String.fromInt i
                , parentId =
                    if i < fanout then
                        Nothing

                    else
                        Just (cardId (i // fanout - 1))
                , position = toFloat (modBy fanout i)
                , deleted = False
                , synced = synced
                , updatedAt = UpdatedAt.fromParts (1000 + i) 0 ("hash-" ++ String.fromInt i)
                }
            )


cardId : Int -> String
cardId i =
    "c" ++ String.fromInt i


{-| How many of `docRows`' cards are in the subtree of its first card, itself
included.

Counted by arithmetic rather than by searching the document: the children of a
contiguous run of ids are themselves a contiguous run (card `i`'s children are
`fanout * (i + 1)` and the nine ids after it), so one range per level of the
tree, clipped at the last card, is the whole answer. A search per node would
make this helper the slowest thing in the file.

-}
firstCardSubtreeSize : Int -> Int
firstCardSubtreeSize count =
    let
        childrenOfRange ( low, high ) =
            ( fanout * (low + 1), fanout * (high + 1) + fanout - 1 )

        levels ( low, high ) total =
            let
                lastPresent =
                    min high (count - 1)
            in
            if low > lastPresent then
                total

            else
                levels (childrenOfRange ( low, lastPresent )) (total + lastPresent - low + 1)
    in
    levels ( 0, 0 ) 0


encodeRows : List (Data.Card_tests_only UpdatedAt) -> Enc.Value
encodeRows rows =
    let
        encodeRow row =
            Enc.object
                [ ( "id", Enc.string row.id )
                , ( "treeId", Enc.string row.treeId )
                , ( "content", Enc.string row.content )
                , ( "parentId", row.parentId |> Maybe.map Enc.string |> Maybe.withDefault Enc.null )
                , ( "position", Enc.float row.position )
                , ( "deleted"
                  , Enc.int
                        (if row.deleted then
                            1

                         else
                            0
                        )
                  )
                , ( "synced", Enc.bool row.synced )
                , ( "updatedAt", UpdatedAt.encode row.updatedAt )
                ]
    in
    Enc.list encodeRow rows


{-| The document as `Doc.Data` materializes it, and what it says to the server.
-}
received : List (Data.Card_tests_only UpdatedAt) -> Result String { tree : Tree, outMsg : List Outgoing.Msg }
received rows =
    case Data.cardDataReceived (encodeRows rows) ( Data.emptyCardBased, Tree "0" "" (Children []), "tree1" ) of
        Err err ->
            Err err

        Ok Nothing ->
            Err "expected the card rows to change the document"

        Ok (Just { newTree, outMsg }) ->
            Ok { tree = newTree, outMsg = outMsg }


{-| The tree built the way `treeHelper` used to build it: for every node, a
filter of the entire card list for the cards naming it as their parent.
-}
naiveTree : List (Data.Card_tests_only UpdatedAt) -> Tree
naiveTree rows =
    Tree "0" "" (Children (naiveChildren rows Nothing))


naiveChildren : List (Data.Card_tests_only UpdatedAt) -> Maybe String -> List Tree
naiveChildren rows parentId =
    rows
        |> List.filter (\row -> row.parentId == parentId)
        |> List.sortBy (\row -> ( row.position, row.id ))
        |> List.map (\row -> Tree row.id row.content (Children (naiveChildren rows (Just row.id))))


{-| Nodes below the "0" root, which is not a card.
-}
cardCount : Tree -> Int
cardCount tree =
    case tree.children of
        Children children ->
            List.sum (List.map (\child -> 1 + cardCount child) children)


deltaIds : List Outgoing.Msg -> Result String (List String)
deltaIds msgs =
    msgs
        |> List.filterMap
            (\msg ->
                case msg of
                    Outgoing.PushDeltas value ->
                        Just value

                    _ ->
                        Nothing
            )
        |> List.head
        |> Maybe.map
            (Dec.decodeValue (Dec.field "dlts" (Dec.list (Dec.field "id" Dec.string)))
                >> Result.mapError Dec.errorToString
            )
        |> Maybe.withDefault (Err "expected a PushDeltas message")


deletedIds : Enc.Value -> Result String (List String)
deletedIds save =
    save
        |> Dec.decodeValue
            (Dec.field "toMarkDeleted"
                (Dec.list
                    (Dec.map2 Tuple.pair
                        (Dec.field "id" Dec.string)
                        (Dec.field "deleted" Dec.int)
                    )
                )
            )
        |> Result.mapError Dec.errorToString
        |> Result.map (List.filter (\( _, deleted ) -> deleted == 1) >> List.map Tuple.first)


{-| The document these tests put through `Doc.Data`.

Five thousand cards is the size ticket 25 set out to keep responsive, and it is
above the size where the quadratic version of this code stopped working
altogether: grouping the version log by card id recursed once per card, so a
document of about four thousand cards overflowed the JavaScript stack on the
first card-rows echo -- the document could not be opened at all.

-}
documentSize : Int
documentSize =
    5000


{-| The document the tree below is compared against a filter-per-node walk.

Smaller than the rest, because the naive walk it is compared against is the
quadratic algorithm: at five thousand cards the reference alone takes some three
seconds, and it is the comparison that carries the meaning here, not the size.

-}
comparisonSize : Int
comparisonSize =
    1000


suite : Test
suite =
    describe "Doc.Data at five thousand cards (CODE_REVIEW.md P1)"
        [ test "materializes every card of the document" <|
            \_ ->
                docRows True documentSize
                    |> received
                    |> Result.map (\{ tree } -> cardCount tree)
                    |> Expect.equal (Ok documentSize)
        , test "materializes the same tree as a filter-per-node walk" <|
            \_ ->
                let
                    rows =
                        docRows True comparisonSize
                in
                rows
                    |> received
                    |> Result.map .tree
                    |> Expect.equal (Ok (naiveTree rows))
        , test "a fully synced document has nothing to say to the server" <|
            \_ ->
                docRows True documentSize
                    |> received
                    |> Result.map .outMsg
                    |> Expect.equal (Ok [])
        , test "an unsynced document pushes one insert delta per card" <|
            \_ ->
                docRows False documentSize
                    |> received
                    |> Result.andThen (.outMsg >> deltaIds)
                    |> Expect.equal (Ok (List.range 0 (documentSize - 1) |> List.map cardId))
        , test "deleting a card stages its whole subtree" <|
            \_ ->
                let
                    ( _, save ) =
                        Data.localSave "tree1"
                            (CTRmv (cardId 0))
                            (Data.model_tests_only (docRows True documentSize) Nothing)
                in
                deletedIds save
                    |> Result.map List.length
                    |> Expect.equal (Ok (firstCardSubtreeSize documentSize))
        ]
