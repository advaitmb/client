module DataTest exposing (suite)

{-| Tests at ADR-0001 seam 1: the `Doc.Data` public API.

`localSave` is asserted through the JSON it hands the port layer (the
`DBChangeLists` shape `src/shared/doc.js` persists to Dexie), decoded
field-by-field rather than compared as a string, because the field names
are the contract and the key order is not.

The version log is append-mostly (Dexie's `cards` primary key is
`updatedAt`), so several rows per card id coexist and stale rows survive
until push + fast-forward. ADR-0005 §1 makes newest-row-per-id the only
legal view of that log, so the fixtures below deliberately keep stale rows
around, in an order a raw-row scan would trip over.

-}

import Dict
import Doc.Data as Data
import Expect
import Json.Decode as Dec
import Json.Encode as Enc
import Outgoing
import Set
import Test exposing (Test, describe, test)
import Types exposing (CardTreeOp(..), Children(..), ConflictSelection(..), Tree)
import UpdatedAt exposing (UpdatedAt)


{-| A synced version row, as it would sit in the Dexie `cards` table.
-}
syncedRow :
    { id : String, parentId : Maybe String, position : Float, content : String, ts : Int }
    -> Data.Card_tests_only UpdatedAt
syncedRow { id, parentId, position, content, ts } =
    { id = id
    , treeId = "tree1"
    , content = content
    , parentId = parentId
    , position = position
    , deleted = False
    , synced = True
    , updatedAt = UpdatedAt.fromParts ts 0 ("hash-" ++ id ++ "-" ++ String.fromInt ts)
    }


{-| A synced version row that marks its card deleted.
-}
deletedRow :
    { id : String, parentId : Maybe String, position : Float, content : String, ts : Int }
    -> Data.Card_tests_only UpdatedAt
deletedRow args =
    let
        row =
            syncedRow args
    in
    { row | deleted = True }


{-| An unsynced version row: one offline save, not pushed to the server yet.
-}
unsyncedRow :
    { id : String, parentId : Maybe String, position : Float, content : String, ts : Int }
    -> Data.Card_tests_only UpdatedAt
unsyncedRow args =
    let
        row =
            syncedRow args
    in
    { row | synced = False }


{-| A version row that marks its card deleted, with the deletion not pushed yet.
-}
unsyncedDeletedRow :
    { id : String, parentId : Maybe String, position : Float, content : String, ts : Int }
    -> Data.Card_tests_only UpdatedAt
unsyncedDeletedRow args =
    let
        row =
            deletedRow args
    in
    { row | synced = False }


{-| The `cards` rows as `src/shared/doc.js` hands them to Elm.
-}
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


{-| History snapshots as `src/shared/doc.js` hands them to Elm: one entry per
snapshot, its `data` the card rows alive when it was taken. The port builds a
snapshot from the newest row per card id with the deleted cards dropped, and
forces `deleted = 0` on every row it passes on, so a deleted card is simply
absent from a snapshot.
-}
encodeHistory : List ( String, Int, List (Data.Card_tests_only UpdatedAt) ) -> Enc.Value
encodeHistory snapshots =
    let
        encodeSnapshot ( id, ts, rows ) =
            Enc.object
                [ ( "snapshot", Enc.string id )
                , ( "ts", Enc.int ts )
                , ( "data", encodeRows rows )
                ]
    in
    Enc.list encodeSnapshot snapshots


{-| `historyReceived` for a payload the test built itself.

It decodes by construction, so the `Err` branch is unreachable here; the
fallback is a document with nothing in it rather than the model back unchanged,
so that a regression shows up as an obviously empty result instead of passing
quietly.

-}
receiveHistory : Enc.Value -> Data.Model -> Data.Model
receiveHistory json model =
    Data.historyReceived json model
        |> Result.withDefault Data.emptyCardBased



-- Decoding the DBChangeLists JSON that localSave emits


type alias StagedRow =
    { id : String
    , treeId : String
    , content : String
    , parentId : Maybe String
    , position : Float
    , deleted : Int
    , synced : Bool
    }


type alias ChangeLists =
    { treeId : String
    , toAdd : List StagedRow
    , toMarkSynced : List Dec.Value
    , toMarkDeleted : List StagedRow
    , toRemove : List String
    }


stagedRowDecoder : Dec.Decoder StagedRow
stagedRowDecoder =
    Dec.map7 StagedRow
        (Dec.field "id" Dec.string)
        (Dec.field "treeId" Dec.string)
        (Dec.field "content" Dec.string)
        (Dec.field "parentId" (Dec.maybe Dec.string))
        (Dec.field "position" Dec.float)
        (Dec.field "deleted" Dec.int)
        (Dec.field "synced" Dec.bool)


{-| `treeId` is required of every save: which document a save is for is the
payload's to say, not the port layer's to remember (CODE_REVIEW.md D5).
-}
changeListsDecoder : Dec.Decoder ChangeLists
changeListsDecoder =
    Dec.map5 ChangeLists
        (Dec.field "treeId" Dec.string)
        (Dec.field "toAdd" (Dec.list stagedRowDecoder))
        (Dec.field "toMarkSynced" (Dec.list Dec.value))
        (Dec.field "toMarkDeleted" (Dec.list stagedRowDecoder))
        (Dec.field "toRemove" (Dec.list Dec.string))


{-| The payload of the `SaveCardBased` message Elm hands the port layer.
-}
savePayload : List Outgoing.Msg -> Maybe Dec.Value
savePayload msgs =
    msgs
        |> List.filterMap
            (\msg ->
                case msg of
                    Outgoing.SaveCardBased value ->
                        Just value

                    _ ->
                        Nothing
            )
        |> List.head



-- Decoding the delta push that goes to the server


type alias PushedOp =
    { t : String, content : Maybe String, expectedVersion : Maybe String }


type alias PushedDelta =
    { id : String, ts : String, ops : List PushedOp }


pushedOpDecoder : Dec.Decoder PushedOp
pushedOpDecoder =
    Dec.map3 PushedOp
        (Dec.field "t" Dec.string)
        (Dec.maybe (Dec.field "c" Dec.string))
        (Dec.maybe (Dec.field "e" Dec.string))


pushedDeltaDecoder : Dec.Decoder PushedDelta
pushedDeltaDecoder =
    Dec.map3 PushedDelta
        (Dec.field "id" Dec.string)
        (Dec.field "ts" Dec.string)
        (Dec.field "ops" (Dec.list pushedOpDecoder))


{-| The deltas of the `PushDeltas` message, or none when there is no such
message because nothing is left to push.
-}
pushedDeltas : List Outgoing.Msg -> Result String (List PushedDelta)
pushedDeltas msgs =
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
            (Dec.decodeValue (Dec.field "dlts" (Dec.list pushedDeltaDecoder))
                >> Result.mapError Dec.errorToString
            )
        |> Maybe.withDefault (Ok [])


{-| How many `PushDeltas` messages were sent. Sending one that carries no
deltas is not a way of saying "nothing to push": the server reads
`dlts[dlts.length - 1].ts` before it looks at the list.
-}
pushMessageCount : List Outgoing.Msg -> Int
pushMessageCount msgs =
    msgs
        |> List.filter
            (\msg ->
                case msg of
                    Outgoing.PushDeltas _ ->
                        True

                    _ ->
                        False
            )
        |> List.length



-- Resolving a content conflict (ADR-0005 §2)


{-| Card "a" was edited offline three times against a synced original, and the
server has a newer conflicting version of it. Card "b" is not in conflict, but
carries an unsynced offline edit of its own.
-}
conflictedRows : List (Data.Card_tests_only UpdatedAt)
conflictedRows =
    [ syncedRow { id = "a", parentId = Nothing, position = 1, content = "Original", ts = 1000 }
    , unsyncedRow { id = "a", parentId = Nothing, position = 1, content = "Edit 1", ts = 2000 }
    , unsyncedRow { id = "a", parentId = Nothing, position = 1, content = "Edit 2", ts = 3000 }
    , unsyncedRow { id = "a", parentId = Nothing, position = 1, content = "Edit 3", ts = 4000 }
    , syncedRow { id = "a", parentId = Nothing, position = 1, content = "Their edit", ts = 5000 }
    , syncedRow { id = "b", parentId = Just "a", position = 1, content = "Child", ts = 1000 }
    , unsyncedRow { id = "b", parentId = Just "a", position = 1, content = "Child edit", ts = 2500 }
    ]


{-| Card "a"'s synced original followed by its three offline edits: the rows a
resolution discards. Their version (5000) is not among them -- it is the row the
card is left with. `List.take 3` drops the newest, the one picking Ours keeps.
-}
ourLineStamps : List String
ourLineStamps =
    [ "1000:0:hash-a-1000", "2000:0:hash-a-2000", "3000:0:hash-a-3000", "4000:0:hash-a-4000" ]


{-| The delta card "b" pushes in every scenario below: resolving card "a"'s
conflict must not touch another card's unsynced work.
-}
childDelta : PushedDelta
childDelta =
    { id = "b"
    , ts = "2500:0:hash-b-2500"
    , ops = [ { t = "u", content = Just "Child edit", expectedVersion = Just "1000:0:hash-b-1000" } ]
    }


{-| What resolving `conflictedRows` leaves behind, seen from the seam: the
staged changes, the unsynced rows still in the DB afterwards, and the delta
push that follows.

A card with no unsynced row left and no delta of its own is a card that
classifies as `Synced`: those two fields are how the tests say so.

-}
type alias Resolution =
    { changes : ChangeLists
    , unsyncedAfter : List ( String, String )
    , pushedAfter : List PushedDelta
    }


{-| Receive `conflictedRows` (so the conflict under test is the one
`getSyncState` actually reports), resolve it as `selection`, apply the staged
save the way the port layer would, then look at what the next push carries.
-}
resolveAs : ConflictSelection -> Result String Resolution
resolveAs selection =
    case Data.cardDataReceived (encodeRows conflictedRows) ( Data.emptyCardBased, Tree "0" "" (Children []), "tree1" ) of
        Ok Nothing ->
            Err "expected cardDataReceived to report the received rows"

        Err err ->
            Err ("cardDataReceived could not read the rows: " ++ err)

        Ok (Just { newData }) ->
            if not (Data.hasConflicts newData) then
                Err "expected the offline edits to be reported as a conflict for the user to resolve"

            else
                case
                    Data.resolveConflicts "tree1" selection newData
                        |> Maybe.map List.singleton
                        |> Maybe.withDefault []
                        |> savePayload
                        |> Maybe.map (Dec.decodeValue changeListsDecoder)
                of
                    Nothing ->
                        Err "expected resolveConflicts to stage a save"

                    Just (Err err) ->
                        Err (Dec.errorToString err)

                    Just (Ok changes) ->
                        let
                            rowsAfter =
                                applySave 6000 changes conflictedRows

                            pushAfter =
                                Data.triggeredPush (Data.model_tests_only rowsAfter Nothing) "tree1"
                        in
                        pushedDeltas pushAfter
                            |> Result.map
                                (\pushed ->
                                    { changes = { changes | toRemove = List.sort changes.toRemove }
                                    , unsyncedAfter =
                                        rowsAfter
                                            |> List.filter (not << .synced)
                                            |> List.map (\row -> ( row.id, row.content ))
                                            |> List.sort
                                    , pushedAfter = pushed
                                    }
                                )


{-| The port layer's half of a save (`src/shared/doc.js`): drop every row named
in `toRemove`, then write each staged row -- `toAdd` and `toMarkDeleted` alike --
with the fresh stamp the port gives it as it writes, which makes it the newest
row of its card. (The port stamps the deletion batch from one timestamp and
`toAdd` from the HLC; either way no staged row is older than the rows it
supersedes, which is all these tests depend on.)
-}
applySave : Int -> ChangeLists -> List (Data.Card_tests_only UpdatedAt) -> List (Data.Card_tests_only UpdatedAt)
applySave ts changes rows =
    let
        removed =
            changes.toRemove |> List.filterMap (UpdatedAt.fromString >> Result.toMaybe)

        stampStaged staged =
            { id = staged.id
            , treeId = staged.treeId
            , content = staged.content
            , parentId = staged.parentId
            , position = staged.position
            , deleted = staged.deleted == 1
            , synced = staged.synced
            , updatedAt = UpdatedAt.fromParts ts 0 ("hash-" ++ staged.id ++ "-" ++ String.fromInt ts)
            }
    in
    (rows |> List.filter (\row -> not (List.any (UpdatedAt.areEqual row.updatedAt) removed)))
        ++ (changes.toAdd |> List.map stampStaged)
        ++ (changes.toMarkDeleted |> List.map stampStaged)


-- Restoring a history snapshot (CODE_REVIEW.md D9)


snapshotId : String
snapshotId =
    "2000:tree1"


{-| The document as it stands now, in an order a raw-row scan would trip over.

The snapshot below was taken when `a`, `b`, `f` and `g` were alive. Since then
`b` was edited offline, `c` was added, `f` was deleted, and `g` was given a new
stamp for the same state (what the server does to a card an op-less delta names).
`d` and `e` were already deleted when the snapshot was taken -- `d`'s deletion
pushed, `e`'s still unsynced -- so, like every card ever deleted, neither is in
it.

-}
rowsBeforeRestore : List (Data.Card_tests_only UpdatedAt)
rowsBeforeRestore =
    [ syncedRow { id = "a", parentId = Nothing, position = 1, content = "Root", ts = 1000 }
    , unsyncedRow { id = "b", parentId = Just "a", position = 1, content = "Child, edited since", ts = 4000 }
    , syncedRow { id = "b", parentId = Just "a", position = 1, content = "Child", ts = 1000 }
    , syncedRow { id = "c", parentId = Just "a", position = 2, content = "Added since", ts = 3000 }
    , deletedRow { id = "d", parentId = Just "a", position = 3, content = "Deleted before the snapshot", ts = 1200 }
    , unsyncedDeletedRow { id = "e", parentId = Just "a", position = 4, content = "Deleted offline before the snapshot", ts = 1500 }
    , syncedRow { id = "e", parentId = Just "a", position = 4, content = "Deleted offline before the snapshot", ts = 900 }
    , deletedRow { id = "f", parentId = Just "a", position = 5, content = "Deleted since the snapshot", ts = 3500 }
    , syncedRow { id = "g", parentId = Just "a", position = 6, content = "Stable", ts = 3000 }
    ]


{-| The rows the snapshot holds: the cards alive when it was taken, with the
content, parent and position they had then.
-}
snapshotRows : List (Data.Card_tests_only UpdatedAt)
snapshotRows =
    [ syncedRow { id = "a", parentId = Nothing, position = 1, content = "Root", ts = 1000 }
    , syncedRow { id = "b", parentId = Just "a", position = 1, content = "Child", ts = 1000 }
    , syncedRow { id = "f", parentId = Just "a", position = 5, content = "Deleted since the snapshot", ts = 1000 }
    , syncedRow { id = "g", parentId = Just "a", position = 6, content = "Stable", ts = 1000 }
    ]


{-| A tree as `Import.Single` decodes one: a root wrapper holding the cards.
-}
importedTree : Tree
importedTree =
    Tree "0"
        ""
        (Children
            [ Tree "r" "Imported root" (Children [ Tree "c" "Imported child" (Children []) ]) ]
        )


{-| The save `restore` stages for that snapshot, decoded.
-}
restoreChanges : Result String ChangeLists
restoreChanges =
    Data.model_tests_only rowsBeforeRestore Nothing
        |> receiveHistory (encodeHistory [ ( snapshotId, 2000, snapshotRows ) ])
        |> (\model -> Data.restore "tree1" model snapshotId)
        |> savePayload
        |> Maybe.map (Dec.decodeValue changeListsDecoder >> Result.mapError Dec.errorToString)
        |> Maybe.withDefault (Err "expected restore to stage a save")


{-| The document after the restore: the staged save applied the way the port
layer applies it, then handed back to Elm the way the Dexie liveQuery does. The
tree is what the user is left looking at; the deltas are what the server is told.
-}
restoredDoc : Result String { tree : Tree, pushed : List PushedDelta }
restoredDoc =
    restoreChanges
        |> Result.andThen
            (\changes ->
                let
                    rowsAfter =
                        applySave 6000 changes rowsBeforeRestore
                in
                case Data.cardDataReceived (encodeRows rowsAfter) ( Data.emptyCardBased, Tree "0" "" (Children []), "tree1" ) of
                    Ok Nothing ->
                        Err "expected cardDataReceived to report the restored rows"

                    Err err ->
                        Err ("cardDataReceived could not read the restored rows: " ++ err)

                    Ok (Just { newTree, outMsg }) ->
                        pushedDeltas outMsg
                            |> Result.map (\pushed -> { tree = newTree, pushed = pushed })
            )


-- Card positions (CODE_REVIEW.md D8)


{-| Every `mov` op in a push, as ( card id, position ).

A rebalance says what it did in `mov` ops like any other move, so this is how
the tests read it off the wire. `toDelta` drops op-less deltas (D9), so an op
that shows up here is one the server will act on.

-}
pushedMoves : List Outgoing.Msg -> Result String (List ( String, Float ))
pushedMoves msgs =
    let
        movePosition : Dec.Decoder (Maybe Float)
        movePosition =
            Dec.map2
                (\t pos_ ->
                    if t == "m" then
                        pos_

                    else
                        Nothing
                )
                (Dec.field "t" Dec.string)
                (Dec.maybe (Dec.field "pos" Dec.float))

        deltaMoves : Dec.Decoder (List ( String, Float ))
        deltaMoves =
            Dec.map2
                (\id positions -> positions |> List.filterMap (Maybe.map (Tuple.pair id)))
                (Dec.field "id" Dec.string)
                (Dec.field "ops" (Dec.list movePosition))
    in
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
            (Dec.decodeValue (Dec.field "dlts" (Dec.list deltaMoves))
                >> Result.map (List.concat >> List.sort)
                >> Result.mapError Dec.errorToString
            )
        |> Maybe.withDefault (Ok [])


{-| The ( id, position ) of every row a save stages to add.
-}
stagedPositions : Enc.Value -> Result String (List ( String, Float ))
stagedPositions saved =
    Dec.decodeValue changeListsDecoder saved
        |> Result.mapError Dec.errorToString
        |> Result.map (.toAdd >> List.map (\row -> ( row.id, row.position )))


{-| A document driven the way the app drives it: `localSave` for each editing
operation, the staged changes written the way the port layer writes them
(`applySave`), and the result handed back the way the Dexie liveQuery does.
-}
type alias Doc =
    { model : Data.Model
    , rows : List (Data.Card_tests_only UpdatedAt)
    , tree : Tree
    , outMsg : List Outgoing.Msg
    }


docFrom : List (Data.Card_tests_only UpdatedAt) -> Result String Doc
docFrom rows =
    Ok
        { model = Data.model_tests_only rows Nothing
        , rows = rows
        , tree = Tree "0" "" (Children [])
        , outMsg = []
        }


{-| One editing operation, all the way round: save, write, read back.
-}
step : Int -> CardTreeOp -> Result String Doc -> Result String Doc
step ts op =
    Result.andThen
        (\doc ->
            let
                ( savedModel, saved ) =
                    Data.localSave "tree1" op doc.model
            in
            case Dec.decodeValue changeListsDecoder saved of
                Err err ->
                    Err (Dec.errorToString err)

                Ok changes ->
                    let
                        rowsAfter =
                            applySave ts changes doc.rows
                    in
                    case Data.cardDataReceived (encodeRows rowsAfter) ( savedModel, doc.tree, "tree1" ) of
                        Ok Nothing ->
                            Err "expected cardDataReceived to report the saved rows"

                        Err err ->
                            Err ("cardDataReceived could not read the saved rows: " ++ err)

                        Ok (Just received) ->
                            Ok
                                { model = received.newData
                                , rows = rowsAfter
                                , tree = received.newTree
                                , outMsg = received.outMsg
                                }
        )


{-| `count` cards inserted at the same spot -- always immediately after the one
card the document started with -- each insert a full round trip, so every one of
them sees the positions the one before it wrote.
-}
insertedAtSameSpot : Int -> Result String Doc
insertedAtSameSpot count =
    List.range 1 count
        |> List.foldl
            (\i acc ->
                step (1000 + i * 10)
                    (CTIns ("c" ++ String.fromInt i) ("Card " ++ String.fromInt i) Nothing 1)
                    acc
            )
            -- Position 1, not 0: `(0 + gap) / 2` halves exactly all the way
            -- down to Float's denormals, while a non-zero left neighbour runs
            -- out of mantissa after ~50 halvings -- and every card in a real
            -- document has a non-zero neighbour somewhere.
            (docFrom [ syncedRow { id = "a", parentId = Nothing, position = 1, content = "First", ts = 1000 } ])


{-| The ids of the root cards, in the order the user sees them.
-}
rootOrder : Doc -> List String
rootOrder doc =
    case doc.tree.children of
        Children children ->
            children |> List.map .id


{-| The position of every living root card, read straight off the version log:
the highest-timestamped row of each id. Computed here rather than asked of
`Doc.Data` so the assertion has its own account of what the document says.
-}
rootPositions : Doc -> List Float
rootPositions doc =
    doc.rows
        |> List.foldl
            (\row acc ->
                case Dict.get row.id acc of
                    Just existing ->
                        if UpdatedAt.getTimestamp row.updatedAt > UpdatedAt.getTimestamp existing.updatedAt then
                            Dict.insert row.id row acc

                        else
                            acc

                    Nothing ->
                        Dict.insert row.id row acc
            )
            Dict.empty
        |> Dict.values
        |> List.filter (\row -> row.parentId == Nothing && not row.deleted)
        |> List.map .position


{-| Three root cards with no room left between the first two: the state ~50
same-spot inserts leave behind, one insert before the midpoint stops being a
new number at all.
-}
crowdedRows : List (Data.Card_tests_only UpdatedAt)
crowdedRows =
    [ syncedRow { id = "a", parentId = Nothing, position = 0, content = "First", ts = 1000 }
    , syncedRow { id = "b", parentId = Nothing, position = 1.0e-9, content = "Second", ts = 1000 }
    , syncedRow { id = "z", parentId = Nothing, position = 1, content = "Third", ts = 1000 }
    ]


{-| A document with somewhere to move a card to: `x` at the root, `p` with a
child of its own, and `y` a root card that no operation below touches.
-}
moveTargetRows : List (Data.Card_tests_only UpdatedAt)
moveTargetRows =
    [ syncedRow { id = "p", parentId = Nothing, position = 1, content = "New parent", ts = 1000 }
    , syncedRow { id = "c", parentId = Just "p", position = 0, content = "Child of p", ts = 1000 }
    , syncedRow { id = "x", parentId = Nothing, position = 3, content = "Wanderer", ts = 1000 }
    , syncedRow { id = "y", parentId = Nothing, position = 5, content = "Bystander", ts = 1000 }
    ]



-- Merging two cards (ticket 30)


{-| One merge as a scenario: which way the user merged, and which of the two
cards had children of its own. The four combinations in each direction are what
`mergeCards` decides between.
-}
type alias MergeScenario =
    { isUp : Bool, currentHasChildren : Bool, otherHasChildren : Bool }


{-| The two cards of one merge scenario, with the children it asks for.

`c` is the card the user is on -- the one that survives and keeps its id -- and
`o` is the one it absorbs: the card below it for a merge down, the card above it
for a merge up, so the fixture places them in that order. Children are named
after the card they start under: `cc1`, `cc2` under `c`, `oc1`, `oc2` under `o`.

-}
mergeRows : MergeScenario -> List (Data.Card_tests_only UpdatedAt)
mergeRows { isUp, currentHasChildren, otherHasChildren } =
    let
        ( posOfCurrent, posOfOther ) =
            if isUp then
                ( 1, 0 )

            else
                ( 0, 1 )

        childrenOf parentId =
            [ syncedRow { id = parentId ++ "c1", parentId = Just parentId, position = 0, content = "First child of " ++ parentId, ts = 1000 }
            , syncedRow { id = parentId ++ "c2", parentId = Just parentId, position = 1, content = "Second child of " ++ parentId, ts = 1000 }
            ]
    in
    [ syncedRow { id = "c", parentId = Nothing, position = posOfCurrent, content = "Current", ts = 1000 }
    , syncedRow { id = "o", parentId = Nothing, position = posOfOther, content = "Other", ts = 1000 }
    ]
        ++ (if currentHasChildren then
                childrenOf "c"

            else
                []
           )
        ++ (if otherHasChildren then
                childrenOf "o"

            else
                []
           )


{-| The rows that scenario's merge stages to add, as ( id, parentId, position ):
who the save says each card's parent is now, and where it sits among its
siblings. Every child of the card merged away has to be in here -- the same save
deletes its parent.

Sorted by id: the port layer writes the whole list, so the order it arrives in
says nothing, while the positions in it are the order the user will see.

-}
mergedRows : MergeScenario -> Result String (List ( String, Maybe String, Float ))
mergedRows scenario =
    Data.localSave "tree1" (CTMrg "c" "o" scenario.isUp) (Data.model_tests_only (mergeRows scenario) Nothing)
        |> Tuple.second
        |> Dec.decodeValue changeListsDecoder
        |> Result.mapError Dec.errorToString
        |> Result.map (.toAdd >> List.map (\row -> ( row.id, row.parentId, row.position )) >> List.sortBy (\( id, _, _ ) -> id))


{-| The same merge all the way round -- saved, written, read back -- as the root
cards and the children of `c` the user is left looking at. A child that got no
re-parenting row is simply absent: the tree is built from the root down, so
nothing under a deleted card is reachable.
-}
mergedTree : MergeScenario -> Result String ( List String, List String )
mergedTree scenario =
    docFrom (mergeRows scenario)
        |> step 2000 (CTMrg "c" "o" scenario.isUp)
        |> Result.map (\doc -> ( rootOrder doc, childIdsOf "c" doc.tree ))


{-| The ids of one card's children in a materialized tree, in the order the
user sees them.
-}
childIdsOf : String -> Tree -> List String
childIdsOf cardId tree =
    case tree.children of
        Children children ->
            if tree.id == cardId then
                children |> List.map .id

            else
                children |> List.concatMap (childIdsOf cardId)


{-| Two editing operations inside one Dexie round trip: the second save is built
on the model the first one returned, with no `cardDataReceived` in between.

That is the window every test using this is about. `Doc.Data`'s card rows are
refreshed only by the Dexie liveQuery, so inside it the version log still
describes the document as it was before the first save -- and a save that reads
the log alone writes back the state the first one had just changed.

-}
savedAfter : CardTreeOp -> CardTreeOp -> List (Data.Card_tests_only UpdatedAt) -> Result String ChangeLists
savedAfter firstOp secondOp rows =
    let
        ( afterFirst, _ ) =
            Data.localSave "tree1" firstOp (Data.model_tests_only rows Nothing)

        ( _, secondSave ) =
            Data.localSave "tree1" secondOp afterFirst
    in
    Dec.decodeValue changeListsDecoder secondSave
        |> Result.mapError Dec.errorToString


suite : Test
suite =
    describe "Doc.Data public API (ADR-0001 seam 1)"
        [ test "localSave of an insert stages one unsynced row placed after its sibling" <|
            \_ ->
                let
                    model =
                        Data.model_tests_only
                            [ syncedRow { id = "a", parentId = Nothing, position = 0, content = "First card", ts = 1000 } ]
                            Nothing

                    saved =
                        Data.localSave "tree1" (CTIns "b" "Second card" Nothing 1) model
                            |> Tuple.second
                in
                Dec.decodeValue changeListsDecoder saved
                    |> Expect.equal
                        (Ok
                            { treeId = "tree1"
                            , toAdd =
                                [ { id = "b"
                                  , treeId = "tree1"
                                  , content = "Second card"
                                  , parentId = Nothing
                                  , position = 1
                                  , deleted = 0
                                  , synced = False
                                  }
                                ]
                            , toMarkSynced = []
                            , toMarkDeleted = []
                            , toRemove = []
                            }
                        )
        , test "localSave of an update is based on the newest version row of the card" <|
            \_ ->
                let
                    -- Two version rows for card "a": the newer one moved it
                    -- under "p" at position 5.  The staged update must carry
                    -- the newest row's parentId/position, not the stale row's.
                    model =
                        Data.model_tests_only
                            [ syncedRow { id = "a", parentId = Nothing, position = 0, content = "Original", ts = 1000 }
                            , syncedRow { id = "a", parentId = Just "p", position = 5, content = "Moved", ts = 2000 }
                            , syncedRow { id = "p", parentId = Nothing, position = 1, content = "Parent", ts = 1000 }
                            ]
                            Nothing

                    saved =
                        Data.localSave "tree1" (CTUpd "a" "Edited content") model
                            |> Tuple.second
                in
                Dec.decodeValue changeListsDecoder saved
                    |> Expect.equal
                        (Ok
                            { treeId = "tree1"
                            , toAdd =
                                [ { id = "a"
                                  , treeId = "tree1"
                                  , content = "Edited content"
                                  , parentId = Just "p"
                                  , position = 5
                                  , deleted = 0
                                  , synced = False
                                  }
                                ]
                            , toMarkSynced = []
                            , toMarkDeleted = []
                            , toRemove = []
                            }
                        )
        , test "tree materialization keeps only the newest version per card id" <|
            \_ ->
                let
                    -- Card "a" has two version rows; only the newest content
                    -- may appear, exactly once, with "b" still its child.
                    json =
                        """
                        { "tree": { "name": "Doc" },
                          "cards": [
                            { "id": "a", "treeId": "t", "content": "Old content", "parentId": null, "position": 1, "updatedAt": "1000:0:x" },
                            { "id": "a", "treeId": "t", "content": "New content", "parentId": null, "position": 1, "updatedAt": "2000:0:y" },
                            { "id": "b", "treeId": "t", "content": "Child card", "parentId": "a", "position": 1, "updatedAt": "1500:0:z" }
                          ]
                        }
                        """
                in
                Dec.decodeString Data.publicDataDecoder json
                    |> Expect.equal
                        (Ok
                            ( "Doc"
                            , Tree "0"
                                ""
                                (Children
                                    [ Tree "a"
                                        "New content"
                                        (Children [ Tree "b" "Child card" (Children []) ])
                                    ]
                                )
                            )
                        )
        , test "deleting a card leaves a card that was moved out of it alone" <|
            \_ ->
                let
                    -- Card "x" was moved from "a" to "b", so its stale row
                    -- still claims "a" as parent.  Deleting "a" must not
                    -- touch "x", which now lives under "b".
                    model =
                        Data.model_tests_only
                            [ syncedRow { id = "a", parentId = Nothing, position = 1, content = "Old parent", ts = 1000 }
                            , syncedRow { id = "b", parentId = Nothing, position = 2, content = "New parent", ts = 1000 }
                            , syncedRow { id = "x", parentId = Just "a", position = 1, content = "Moved card", ts = 1000 }
                            , syncedRow { id = "x", parentId = Just "b", position = 1, content = "Moved card", ts = 2000 }
                            ]
                            Nothing

                    saved =
                        Data.localSave "tree1" (CTRmv "a") model
                            |> Tuple.second
                in
                Dec.decodeValue changeListsDecoder saved
                    |> Expect.equal
                        (Ok
                            { treeId = "tree1"
                            , toAdd = []
                            , toMarkSynced = []
                            , toMarkDeleted =
                                [ { id = "a"
                                  , treeId = "tree1"
                                  , content = "Old parent"
                                  , parentId = Nothing
                                  , position = 1
                                  , deleted = 1
                                  , synced = False
                                  }
                                ]
                            , toRemove = []
                            }
                        )
        , test "deleting a card marks its whole visible subtree deleted" <|
            \_ ->
                let
                    model =
                        Data.model_tests_only
                            [ syncedRow { id = "a", parentId = Nothing, position = 1, content = "Parent", ts = 1000 }
                            , syncedRow { id = "z", parentId = Nothing, position = 2, content = "Sibling", ts = 1000 }
                            , syncedRow { id = "x", parentId = Just "a", position = 1, content = "Child", ts = 1000 }
                            , syncedRow { id = "y", parentId = Just "x", position = 1, content = "Grandchild", ts = 1000 }
                            ]
                            Nothing

                    saved =
                        Data.localSave "tree1" (CTRmv "a") model
                            |> Tuple.second
                in
                Dec.decodeValue changeListsDecoder saved
                    |> Result.map (.toMarkDeleted >> List.map .id >> List.sort)
                    |> Expect.equal (Ok [ "a", "x", "y" ])
        , test "merging cards skips a child whose newest version is deleted" <|
            \_ ->
                let
                    -- Child "d" of "o" was deleted, but its stale undeleted
                    -- row survives.  Merging "o" into "c" must neither
                    -- resurrect "d" under "c" nor let its position offset the
                    -- children that do move ("e" keeps position 2, after the
                    -- child "c" already had).
                    model =
                        Data.model_tests_only
                            [ syncedRow { id = "c", parentId = Nothing, position = 1, content = "Current", ts = 1000 }
                            , syncedRow { id = "o", parentId = Nothing, position = 2, content = "Other", ts = 1000 }
                            , syncedRow { id = "cc", parentId = Just "c", position = 1, content = "Child of current", ts = 1000 }
                            , syncedRow { id = "d", parentId = Just "o", position = 1, content = "Deleted child", ts = 1000 }
                            , deletedRow { id = "d", parentId = Just "o", position = 1, content = "Deleted child", ts = 2000 }
                            , syncedRow { id = "e", parentId = Just "o", position = 2, content = "Live child", ts = 1000 }
                            ]
                            Nothing

                    saved =
                        Data.localSave "tree1" (CTMrg "c" "o" False) model
                            |> Tuple.second
                in
                Dec.decodeValue changeListsDecoder saved
                    |> Expect.equal
                        (Ok
                            { treeId = "tree1"
                            , toAdd =
                                [ { id = "c"
                                  , treeId = "tree1"
                                  , content = "Current\n\nOther"
                                  , parentId = Nothing
                                  , position = 1
                                  , deleted = 0
                                  , synced = False
                                  }
                                , { id = "e"
                                  , treeId = "tree1"
                                  , content = "Live child"
                                  , parentId = Just "c"
                                  , position = 2
                                  , deleted = 0
                                  , synced = False
                                  }
                                ]
                            , toMarkSynced = []
                            , toMarkDeleted =
                                [ { id = "o"
                                  , treeId = "tree1"
                                  , content = "Other"
                                  , parentId = Nothing
                                  , position = 2
                                  , deleted = 1
                                  , synced = False
                                  }
                                ]
                            , toRemove = []
                            }
                        )
        , test "merging down into a childless card re-parents the merged card's children" <|
            \_ ->
                -- The card below (`o`) is absorbed and deleted, so its
                -- children have to be re-parented in the same save.  The
                -- surviving card has no children of its own to sit clear of,
                -- so they keep the positions they have.
                mergedRows { isUp = False, currentHasChildren = False, otherHasChildren = True }
                    |> Expect.equal
                        (Ok
                            [ ( "c", Nothing, 0 )
                            , ( "oc1", Just "c", 0 )
                            , ( "oc2", Just "c", 1 )
                            ]
                        )
        , test "the tree after merging down into a childless card keeps the children" <|
            \_ ->
                -- The same merge as the user sees it: `o` is gone from the
                -- root and its children are under `c`.  Without their
                -- re-parenting rows they are under a deleted card, which puts
                -- them out of the tree altogether.
                mergedTree { isUp = False, currentHasChildren = False, otherHasChildren = True }
                    |> Expect.equal (Ok ( [ "c" ], [ "oc1", "oc2" ] ))
        , test "merging up into a childless card re-parents the merged card's children" <|
            \_ ->
                -- The mirror image: the card above (`o`) is the one absorbed,
                -- and its children again have nothing to sit clear of.
                mergedRows { isUp = True, currentHasChildren = False, otherHasChildren = True }
                    |> Expect.equal
                        (Ok
                            [ ( "c", Nothing, 1 )
                            , ( "oc1", Just "c", 0 )
                            , ( "oc2", Just "c", 1 )
                            ]
                        )
        , test "the tree after merging up into a childless card keeps the children" <|
            \_ ->
                mergedTree { isUp = True, currentHasChildren = False, otherHasChildren = True }
                    |> Expect.equal (Ok ( [ "c" ], [ "oc1", "oc2" ] ))
        , test "merging down puts the merged card's children after the surviving card's" <|
            \_ ->
                -- `o` sat below `c`, so its children belong below `c`'s: they
                -- are moved past `c`'s last child (position 1) onto the next
                -- whole numbers, keeping the gaps they had between them.
                mergedRows { isUp = False, currentHasChildren = True, otherHasChildren = True }
                    |> Expect.equal
                        (Ok
                            [ ( "c", Nothing, 0 )
                            , ( "oc1", Just "c", 2 )
                            , ( "oc2", Just "c", 3 )
                            ]
                        )
        , test "merging up puts the merged card's children before the surviving card's" <|
            \_ ->
                -- And the other way round: `o` sat above `c`, so its children
                -- are moved to before `c`'s first child (position 0).
                mergedRows { isUp = True, currentHasChildren = True, otherHasChildren = True }
                    |> Expect.equal
                        (Ok
                            [ ( "c", Nothing, 1 )
                            , ( "oc1", Just "c", -2 )
                            , ( "oc2", Just "c", -1 )
                            ]
                        )
        , test "merging two childless cards stages only the card kept" <|
            \_ ->
                -- Nothing to re-parent in either direction: the merge is the
                -- joined content and the deletion of `o`.
                ( mergedRows { isUp = False, currentHasChildren = False, otherHasChildren = False }
                , mergedRows { isUp = True, currentHasChildren = False, otherHasChildren = False }
                )
                    |> Expect.equal
                        ( Ok [ ( "c", Nothing, 0 ) ]
                        , Ok [ ( "c", Nothing, 1 ) ]
                        )
        , test "merging in a childless card leaves the surviving card's children alone" <|
            \_ ->
                -- The surviving card's own children are not part of a merge:
                -- only the card merged away needs re-parenting rows, and here
                -- it has none in either direction.
                ( mergedRows { isUp = False, currentHasChildren = True, otherHasChildren = False }
                , mergedRows { isUp = True, currentHasChildren = True, otherHasChildren = False }
                )
                    |> Expect.equal
                        ( Ok [ ( "c", Nothing, 0 ) ]
                        , Ok [ ( "c", Nothing, 1 ) ]
                        )
        , test "a remote deletion conflicting with a local edit drops only the pre-deletion row" <|
            \_ ->
                let
                    -- They deleted card "a" (synced row 3000) while we edited
                    -- it offline (unsynced row 2000).  Edits win: the
                    -- pre-deletion synced row is dropped, our unsynced edit is
                    -- left as the row the undelete delta is built from, and no
                    -- extra version is fabricated in its place (which would
                    -- push the pre-conflict content back over our edit).  The
                    -- user is never prompted for a delete-vs-edit conflict.
                    cardsJson =
                        """
                        [ { "id": "a", "treeId": "tree1", "content": "Original", "parentId": null, "position": 1, "deleted": 0, "synced": true, "updatedAt": "1000:0:orig" }
                        , { "id": "a", "treeId": "tree1", "content": "Our edit", "parentId": null, "position": 1, "deleted": 0, "synced": false, "updatedAt": "2000:0:ours" }
                        , { "id": "a", "treeId": "tree1", "content": "Original", "parentId": null, "position": 1, "deleted": 1, "synced": true, "updatedAt": "3000:0:theirs" }
                        ]
                        """

                    cardsValue =
                        Dec.decodeString Dec.value cardsJson
                            |> Result.withDefault Enc.null

                    received =
                        Data.cardDataReceived cardsValue
                            ( Data.emptyCardBased, Tree "0" "" (Children []), "tree1" )
                in
                case received of
                    Ok (Just { newData, outMsg }) ->
                        ( outMsg |> savePayload |> Maybe.map (Dec.decodeValue changeListsDecoder)
                        , Data.hasConflicts newData
                        )
                            |> Expect.equal
                                ( Just
                                    (Ok
                                        { treeId = "tree1"
                                        , toAdd = []
                                        , toMarkSynced = []
                                        , toMarkDeleted = []
                                        , toRemove = [ "1000:0:orig" ]
                                        }
                                    )
                                , False
                                )

                    other ->
                        Expect.fail ("expected cardDataReceived to report the conflict resolution, got " ++ describeReceived other)
        , test "the conflict tree is newest-version-wins, whatever order the rows arrive in" <|
            \_ ->
                let
                    -- Card "a" is not in conflict but has two rows; card "b"
                    -- is.  The selected conflict version of "b" wins even
                    -- though our unsynced row is newer, while "a" resolves to
                    -- its newest row no matter where that row sits in the list.
                    rootNewer =
                        syncedRow { id = "a", parentId = Nothing, position = 1, content = "Newer root", ts = 3000 }

                    rootOlder =
                        syncedRow { id = "a", parentId = Nothing, position = 1, content = "Older root", ts = 1000 }

                    childOriginal =
                        syncedRow { id = "b", parentId = Just "a", position = 1, content = "Original b", ts = 1000 }

                    childTheirs =
                        syncedRow { id = "b", parentId = Just "a", position = 1, content = "Their b", ts = 2000 }

                    childOurs =
                        syncedRow { id = "b", parentId = Just "a", position = 1, content = "Our b", ts = 2500 }

                    allRows =
                        [ rootNewer, rootOlder, childTheirs, childOurs, childOriginal ]

                    conflicts =
                        { original = [ childOriginal ]
                        , ours = [ childOurs ]
                        , theirs = [ childTheirs ]
                        }

                    treeFrom rows =
                        Data.conflictToTree (Data.model_tests_only rows (Just conflicts)) Theirs

                    expected =
                        Just
                            (Tree "0"
                                ""
                                (Children
                                    [ Tree "a"
                                        "Newer root"
                                        (Children [ Tree "b" "Their b" (Children []) ])
                                    ]
                                )
                            )
                in
                ( treeFrom allRows, treeFrom (List.reverse allRows) )
                    |> Expect.equal ( expected, expected )
        , test "resolving as Theirs discards every unsynced row of the card, not just the newest" <|
            \_ ->
                -- Offline editing appends one unsynced row per save, so
                -- discarding only the newest leaves the older ones to
                -- re-classify the card as Unsynced and push content the user
                -- just threw away (ADR-0005 §2).
                resolveAs Theirs
                    |> Expect.equal
                        (Ok
                            { changes =
                                { treeId = "tree1"
                                , toAdd = []
                                , toMarkSynced = []
                                , toMarkDeleted = []
                                , toRemove = ourLineStamps
                                }
                            , unsyncedAfter = [ ( "b", "Child edit" ) ]
                            , pushedAfter = [ childDelta ]
                            }
                        )
        , test "resolving as Original pushes the original content and none of the discarded edits" <|
            \_ ->
                -- Their version is already on the server, so reverting means
                -- pushing the original content back up as a fresh unsynced
                -- row -- and nothing else.
                resolveAs Original
                    |> Expect.equal
                        (Ok
                            { changes =
                                { treeId = "tree1"
                                , toAdd =
                                    [ { id = "a"
                                      , treeId = "tree1"
                                      , content = "Original"
                                      , parentId = Nothing
                                      , position = 1
                                      , deleted = 0
                                      , synced = False
                                      }
                                    ]
                                , toMarkSynced = []
                                , toMarkDeleted = []
                                , toRemove = ourLineStamps
                                }
                            , unsyncedAfter = [ ( "a", "Original" ), ( "b", "Child edit" ) ]
                            , pushedAfter =
                                [ childDelta
                                , { id = "a"
                                  , ts = "6000:0:hash-a-6000"
                                  , ops = [ { t = "u", content = Just "Original", expectedVersion = Just "5000:0:hash-a-5000" } ]
                                  }
                                ]
                            }
                        )
        , test "resolving as Ours keeps exactly the winning newest unsynced row" <|
            \_ ->
                resolveAs Ours
                    |> Expect.equal
                        (Ok
                            { changes =
                                { treeId = "tree1"
                                , toAdd = []
                                , toMarkSynced = []
                                , toMarkDeleted = []

                                -- The winning row ("4000:0:hash-a-4000") stays.
                                , toRemove = ourLineStamps |> List.take 3
                                }
                            , unsyncedAfter = [ ( "a", "Edit 3" ), ( "b", "Child edit" ) ]
                            , pushedAfter =
                                [ childDelta
                                , { id = "a"
                                  , ts = "4000:0:hash-a-4000"
                                  , ops = [ { t = "u", content = Just "Edit 3", expectedVersion = Just "5000:0:hash-a-5000" } ]
                                  }
                                ]
                            }
                        )
        , test "restoring a snapshot stages nothing for cards that are already deleted" <|
            \_ ->
                -- A snapshot holds only living cards, so "absent from the
                -- snapshot" is as true of every card ever deleted (`d`, `e`) as
                -- it is of the cards added since (`c`).  Only the latter may be
                -- deleted; a fresh deletion row per restore for the former is
                -- CODE_REVIEW.md D9.  `g` is the other half of it: a new stamp
                -- for the same content, parent and position is not a change
                -- either.
                restoreChanges
                    |> Expect.equal
                        (Ok
                            { treeId = "tree1"
                            , toAdd =
                                [ { id = "b"
                                  , treeId = "tree1"
                                  , content = "Child"
                                  , parentId = Just "a"
                                  , position = 1
                                  , deleted = 0
                                  , synced = False
                                  }
                                , { id = "f"
                                  , treeId = "tree1"
                                  , content = "Deleted since the snapshot"
                                  , parentId = Just "a"
                                  , position = 5
                                  , deleted = 0
                                  , synced = False
                                  }
                                ]
                            , toMarkSynced = []
                            , toMarkDeleted =
                                [ { id = "c"
                                  , treeId = "tree1"
                                  , content = "Added since"
                                  , parentId = Just "a"
                                  , position = 2
                                  , deleted = 1
                                  , synced = False
                                  }
                                ]
                            , toRemove = []
                            }
                        )
        , test "restoring a snapshot reverts the cards it holds and deletes the cards added since" <|
            \_ ->
                -- What the restore is for: `b` back to its snapshot content,
                -- `f` back from the dead at its snapshot position, `c` gone,
                -- and the cards deleted before the snapshot still gone.
                restoredDoc
                    |> Result.map .tree
                    |> Expect.equal
                        (Ok
                            (Tree "0"
                                ""
                                (Children
                                    [ Tree "a"
                                        "Root"
                                        (Children
                                            [ Tree "b" "Child" (Children [])
                                            , Tree "f" "Deleted since the snapshot" (Children [])
                                            , Tree "g" "Stable" (Children [])
                                            ]
                                        )
                                    ]
                                )
                            )
                        )
        , test "the push after a restore carries an op for every delta and no empty ones" <|
            \_ ->
                -- `e`'s pending deletion still goes up, `c`'s new deletion and
                -- `f`'s undeletion follow it.  Nothing is sent for the cards
                -- the restore left alone -- and nothing empty for `b`, whose
                -- snapshot content is what the server already has.
                restoredDoc
                    |> Result.map .pushed
                    |> Expect.equal
                        (Ok
                            [ { id = "e"
                              , ts = "1500:0:hash-e-1500"
                              , ops = [ { t = "d", content = Nothing, expectedVersion = Just "900:0:hash-e-900" } ]
                              }
                            , { id = "c"
                              , ts = "6000:0:hash-c-6000"
                              , ops = [ { t = "d", content = Nothing, expectedVersion = Just "3000:0:hash-c-3000" } ]
                              }
                            , { id = "f"
                              , ts = "6000:0:hash-f-6000"
                              , ops = [ { t = "ud", content = Nothing, expectedVersion = Nothing } ]
                              }
                            ]
                        )
        , test "a card whose unsynced row matches the server is not pushed at all" <|
            \_ ->
                let
                    -- The row a restore used to leave behind: unsynced, and
                    -- identical to the server's version in every field a delta
                    -- can carry.  There is no op that describes it, and an
                    -- op-less delta is not how you say so -- the server reads
                    -- one as "bump this card's version", writing and
                    -- broadcasting a change nobody made.
                    rows =
                        [ syncedRow { id = "a", parentId = Nothing, position = 1, content = "Same", ts = 1000 }
                        , unsyncedRow { id = "a", parentId = Nothing, position = 1, content = "Same", ts = 2000 }
                        ]
                in
                Data.triggeredPush (Data.model_tests_only rows Nothing) "tree1"
                    |> pushMessageCount
                    |> Expect.equal 0
        , test "restoring the state the document is already in saves nothing" <|
            \_ ->
                let
                    -- Nothing to do: `a` is already what the snapshot says
                    -- (an older stamp for the same state is not a change) and
                    -- `d` is already deleted.  The port layer stamps the tree
                    -- row unsynced for every save it is handed, so a save with
                    -- nothing in it is not free -- and the history view closes
                    -- on an empty message list either way.
                    rows =
                        [ syncedRow { id = "a", parentId = Nothing, position = 1, content = "Root", ts = 1000 }
                        , deletedRow { id = "d", parentId = Just "a", position = 2, content = "Deleted", ts = 1200 }
                        ]

                    snapshot =
                        [ syncedRow { id = "a", parentId = Nothing, position = 1, content = "Root", ts = 900 } ]
                in
                Data.model_tests_only rows Nothing
                    |> receiveHistory (encodeHistory [ ( snapshotId, 2000, snapshot ) ])
                    |> (\model -> Data.restore "tree1" model snapshotId)
                    |> List.length
                    |> Expect.equal 0
        , test "sixty-one inserts at the same spot keep the order they were made in" <|
            \_ ->
                -- Midpoint insertion halves the sibling gap every time, and
                -- after ~50 halvings the midpoint of two Floats *is* one of
                -- them: siblings tie, and `List.sortBy .position` then falls
                -- back on the order the rows came out of Dexie
                -- (CODE_REVIEW.md D8).  Each insert here goes immediately
                -- after `a`, so the newest card is always second.
                insertedAtSameSpot 61
                    |> Result.map rootOrder
                    |> Expect.equal
                        (Ok
                            ("a"
                                :: (List.range 1 61
                                        |> List.reverse
                                        |> List.map (\i -> "c" ++ String.fromInt i)
                                   )
                            )
                        )
        , test "sixty-one inserts at the same spot leave no two siblings sharing a position" <|
            \_ ->
                -- The other half of the same statement, and the one the order
                -- above rests on: a position two cards share is not an order
                -- at all.
                insertedAtSameSpot 61
                    |> Result.map
                        (\doc ->
                            let
                                positions =
                                    rootPositions doc
                            in
                            ( List.length positions, positions |> Set.fromList |> Set.size )
                        )
                    |> Expect.equal (Ok ( 62, 62 ))
        , test "an insert into a gap too small to split rebalances the siblings onto whole numbers" <|
            \_ ->
                -- No room between `a` (0) and `b` (1e-9), so the save renumbers
                -- the siblings instead of splitting the gap: `a` is already
                -- where it belongs and is left alone, the new card takes slot
                -- 1, and `b` and `z` move up to 2 and 3.
                Data.localSave "tree1" (CTIns "n" "New card" Nothing 1) (Data.model_tests_only crowdedRows Nothing)
                    |> Tuple.second
                    |> stagedPositions
                    |> Expect.equal (Ok [ ( "n", 1 ), ( "b", 2 ), ( "z", 3 ) ])
        , test "a rebalanced sibling syncs as an ordinary move" <|
            \_ ->
                -- Rebalanced rows go through the normal save path, so they
                -- reach the server as `mov` ops on the cards that moved -- and
                -- as nothing at all for the sibling that did not.
                docFrom crowdedRows
                    |> step 6000 (CTIns "n" "New card" Nothing 1)
                    |> Result.andThen (.outMsg >> pushedMoves)
                    |> Expect.equal (Ok [ ( "b", 2 ), ( "z", 3 ) ])
        , test "a second insert made before the DB echoes the first lands after it" <|
            \_ ->
                let
                    -- `localSave` reads positions off card rows that only the
                    -- Dexie liveQuery refreshes, so both of these saves see a
                    -- document containing nothing but `a`.  The second one is
                    -- the user pressing Enter twice: it inserts below the card
                    -- the first one created.
                    ( afterFirst, firstSave ) =
                        Data.localSave "tree1"
                            (CTIns "b" "Second" Nothing 1)
                            (Data.model_tests_only
                                [ syncedRow { id = "a", parentId = Nothing, position = 0, content = "First", ts = 1000 } ]
                                Nothing
                            )

                    ( _, secondSave ) =
                        Data.localSave "tree1" (CTIns "c" "Third" Nothing 2) afterFirst
                in
                ( stagedPositions firstSave, stagedPositions secondSave )
                    |> Expect.equal ( Ok [ ( "b", 1 ) ], Ok [ ( "c", 2 ) ] )
        , test "two inserts at the same index before the DB echoes get different positions" <|
            \_ ->
                let
                    -- The same window, asked for the same slot twice: without
                    -- the second save seeing the first one's row, both compute
                    -- the same number.
                    ( afterFirst, firstSave ) =
                        Data.localSave "tree1"
                            (CTIns "b" "Second" Nothing 1)
                            (Data.model_tests_only
                                [ syncedRow { id = "a", parentId = Nothing, position = 0, content = "First", ts = 1000 } ]
                                Nothing
                            )

                    ( _, secondSave ) =
                        Data.localSave "tree1" (CTIns "c" "Third" Nothing 1) afterFirst
                in
                ( stagedPositions firstSave, stagedPositions secondSave )
                    |> Expect.equal ( Ok [ ( "b", 1 ) ], Ok [ ( "c", 0.5 ) ] )
        , test "a move into a gap too small to split rebalances too" <|
            \_ ->
                -- The other caller of the placement: dragging `z` between `a`
                -- and `b` has the same no-room problem as inserting there.
                Data.localSave "tree1" (CTMov "z" Nothing 1) (Data.model_tests_only crowdedRows Nothing)
                    |> Tuple.second
                    |> stagedPositions
                    |> Expect.equal (Ok [ ( "z", 1 ), ( "b", 2 ) ])

        -- Importing a JSON tree (CODE_REVIEW.md D5)
        --
        -- The save an import hands over is for a document that is not the one
        -- on screen -- nothing has opened it yet -- and it travels in the same
        -- unordered `Cmd.batch` as the message that creates that document. So
        -- it has to name the document itself.
        , test "importing a tree stages every card of it, for the document being imported into" <|
            \_ ->
                Data.importTree "imported-doc" importedTree
                    |> Dec.decodeValue changeListsDecoder
                    |> Result.mapError Dec.errorToString
                    |> Result.map
                        (\changes ->
                            { savingInto = changes.treeId
                            , staged = changes.toAdd |> List.map (\row -> ( row.id, row.treeId, row.parentId ))
                            }
                        )
                    |> Expect.equal
                        (Ok
                            { savingInto = "imported-doc"
                            , staged =
                                [ ( "r", "imported-doc", Nothing )
                                , ( "c", "imported-doc", Just "r" )
                                ]
                            }
                        )

        -- Saves built inside one Dexie round trip (ticket 29)
        --
        -- Every operation on an existing card writes a row carrying that
        -- card's whole state, built from the version log -- which the Dexie
        -- liveQuery refreshes one round trip *after* the save that changed it.
        -- So a second operation inside that window writes back the state the
        -- first one had just changed, reverting it.
        , test "an edit made before the DB echoes a move keeps the new parent and position" <|
            \_ ->
                -- The move is already with the port layer, so the version log
                -- still has `x` at the root: an update built from the log alone
                -- carries the old parentId/position and undoes the move.
                moveTargetRows
                    |> savedAfter (CTMov "x" (Just "p") 1) (CTUpd "x" "Edited")
                    |> Result.map .toAdd
                    |> Expect.equal
                        (Ok
                            [ { id = "x"
                              , treeId = "tree1"
                              , content = "Edited"
                              , parentId = Just "p"
                              , position = 1
                              , deleted = 0
                              , synced = False
                              }
                            ]
                        )
        , test "a move made before the DB echoes an edit keeps the new content" <|
            \_ ->
                -- The same window, the other way round: a move row carries the
                -- card's whole state, so one built from the log reverts the
                -- edit the user just made.
                [ syncedRow { id = "a", parentId = Nothing, position = 0, content = "First", ts = 1000 }
                , syncedRow { id = "x", parentId = Nothing, position = 1, content = "Original", ts = 1000 }
                ]
                    |> savedAfter (CTUpd "x" "Edited") (CTMov "x" Nothing 0)
                    |> Result.map .toAdd
                    |> Expect.equal
                        (Ok
                            [ { id = "x"
                              , treeId = "tree1"
                              , content = "Edited"
                              , parentId = Nothing
                              , position = -1
                              , deleted = 0
                              , synced = False
                              }
                            ]
                        )
        , test "removing a card after moving a child out of it leaves the child alone" <|
            \_ ->
                -- CODE_REVIEW.md D1 through the staging window: the log still
                -- has `x` under `a`, but the user has just moved it to `b`.
                [ syncedRow { id = "a", parentId = Nothing, position = 0, content = "Old parent", ts = 1000 }
                , syncedRow { id = "b", parentId = Nothing, position = 1, content = "New parent", ts = 1000 }
                , syncedRow { id = "x", parentId = Just "a", position = 0, content = "Moved out", ts = 1000 }
                ]
                    |> savedAfter (CTMov "x" (Just "b") 0) (CTRmv "a")
                    |> Result.map (.toMarkDeleted >> List.map .id >> List.sort)
                    |> Expect.equal (Ok [ "a" ])
        , test "removing a card after moving a child into it marks the child deleted too" <|
            \_ ->
                -- And the other direction: a card moved into the subtree being
                -- deleted goes with it, or it survives as a child of a deleted
                -- parent.
                [ syncedRow { id = "a", parentId = Nothing, position = 0, content = "Doomed parent", ts = 1000 }
                , syncedRow { id = "b", parentId = Nothing, position = 1, content = "Old parent", ts = 1000 }
                , syncedRow { id = "x", parentId = Just "b", position = 0, content = "Moved in", ts = 1000 }
                ]
                    |> savedAfter (CTMov "x" (Just "a") 0) (CTRmv "a")
                    |> Result.map (.toMarkDeleted >> List.map .id >> List.sort)
                    |> Expect.equal (Ok [ "a", "x" ])
        , test "merging a card after editing it keeps the edit" <|
            \_ ->
                -- A merge writes the joined content as one new row for the
                -- card kept, so a merge built from the log drops the edit that
                -- has not been echoed back yet.
                [ syncedRow { id = "c", parentId = Nothing, position = 0, content = "Current", ts = 1000 }
                , syncedRow { id = "o", parentId = Nothing, position = 1, content = "Other", ts = 1000 }
                ]
                    |> savedAfter (CTUpd "c" "Current, edited") (CTMrg "c" "o" False)
                    |> Result.map .toAdd
                    |> Expect.equal
                        (Ok
                            [ { id = "c"
                              , treeId = "tree1"
                              , content = "Current, edited\n\nOther"
                              , parentId = Nothing
                              , position = 0
                              , deleted = 0
                              , synced = False
                              }
                            ]
                        )
        , test "merging carries along a child moved into the other card before the echo" <|
            \_ ->
                -- The merge deletes `o`, so every child the user has just moved
                -- into it has to be re-parented in the same save -- otherwise
                -- it is left under a deleted card.
                [ syncedRow { id = "c", parentId = Nothing, position = 0, content = "Current", ts = 1000 }
                , syncedRow { id = "o", parentId = Nothing, position = 1, content = "Other", ts = 1000 }
                , syncedRow { id = "cc", parentId = Just "c", position = 0, content = "Child of current", ts = 1000 }
                , syncedRow { id = "x", parentId = Just "c", position = 1, content = "Moved into other", ts = 1000 }
                ]
                    |> savedAfter (CTMov "x" (Just "o") 0) (CTMrg "c" "o" False)
                    |> Result.map (.toAdd >> List.map (\row -> ( row.id, row.parentId, row.position )))
                    |> Expect.equal (Ok [ ( "c", Nothing, 0 ), ( "x", Just "c", 1 ) ])
        , test "a save for one card is not built from another card's staged row" <|
            \_ ->
                -- The staged rows answer for the cards they name and no
                -- others: `y` is untouched by the move, so its update is built
                -- from its own newest row in the log.
                moveTargetRows
                    |> savedAfter (CTMov "x" (Just "p") 1) (CTUpd "y" "Edited bystander")
                    |> Result.map .toAdd
                    |> Expect.equal
                        (Ok
                            [ { id = "y"
                              , treeId = "tree1"
                              , content = "Edited bystander"
                              , parentId = Nothing
                              , position = 5
                              , deleted = 0
                              , synced = False
                              }
                            ]
                        )
        , test "an edit of a card deleted before the echo does not resurrect it" <|
            \_ ->
                -- The staged row of a card just deleted says so, and an
                -- update built on it stays a deleted row.  Reading the log
                -- alone wrote back an undeleted row instead, resurrecting the
                -- card the delete had just removed.
                [ syncedRow { id = "a", parentId = Nothing, position = 0, content = "Root", ts = 1000 }
                , syncedRow { id = "x", parentId = Just "a", position = 0, content = "Doomed", ts = 1000 }
                ]
                    |> savedAfter (CTRmv "x") (CTUpd "x" "Edited")
                    |> Result.map .toAdd
                    |> Expect.equal
                        (Ok
                            [ { id = "x"
                              , treeId = "tree1"
                              , content = "Edited"
                              , parentId = Just "a"
                              , position = 0
                              , deleted = 1
                              , synced = False
                              }
                            ]
                        )
        , test "an echo with no row for a staged card does not forget it" <|
            \_ ->
                let
                    -- `b`'s insert is with the port layer when a collaborator's
                    -- edit of `a` arrives, and any write to the table fires the
                    -- liveQuery.  The echo is the whole card set of the open
                    -- document, so having no row for `b` at all proves `b`'s
                    -- write has not landed -- and the staged row is still the
                    -- only knowledge of it there is.
                    ( afterInsert, _ ) =
                        Data.localSave "tree1"
                            (CTIns "b" "Second" Nothing 1)
                            (Data.model_tests_only
                                [ syncedRow { id = "a", parentId = Nothing, position = 0, content = "First", ts = 1000 } ]
                                Nothing
                            )

                    echoed =
                        Data.cardDataReceived
                            (encodeRows
                                [ syncedRow { id = "a", parentId = Nothing, position = 0, content = "First", ts = 1000 }
                                , syncedRow { id = "a", parentId = Nothing, position = 0, content = "Edited elsewhere", ts = 2000 }
                                ]
                            )
                            ( afterInsert, Tree "0" "" (Children []), "tree1" )
                in
                case echoed of
                    Ok (Just { newData }) ->
                        Data.localSave "tree1" (CTIns "c" "Third" Nothing 1) newData
                            |> Tuple.second
                            |> stagedPositions
                            |> Expect.equal (Ok [ ( "c", 0.5 ) ])

                    other ->
                        Expect.fail ("expected cardDataReceived to report the received rows, got " ++ describeReceived other)

        -- Malformed payloads (CODE_REVIEW.md E16). Each of these three used to
        -- answer a payload it could not read the same way it answers "nothing
        -- changed" -- `Nothing`, or the model back unaltered -- so the document
        -- froze or the history stayed empty with nothing said. The reason the
        -- decoder gives has to come back out, because it is the only
        -- description of what went wrong that anything has.
        , test "card data that does not decode reports the reason instead of looking unchanged" <|
            \_ ->
                Data.cardDataReceived
                    (Enc.list identity
                        [ Enc.object
                            [ ( "id", Enc.string "a" )
                            , ( "treeId", Enc.string "tree1" )
                            , ( "content", Enc.string "Root" )
                            , ( "parentId", Enc.null )

                            -- The server (or a newer client) sent a string here.
                            , ( "position", Enc.string "1" )
                            , ( "deleted", Enc.int 0 )
                            , ( "synced", Enc.bool True )
                            , ( "updatedAt", Enc.string "1000:0:hash-a-1000" )
                            ]
                        ]
                    )
                    ( Data.emptyCardBased, Tree "0" "" (Children []), "tree1" )
                    |> Result.mapError (String.contains "position")
                    |> Expect.equal (Err True)
        , test "an unchanged card payload is still reported as no change, not as an error" <|
            \_ ->
                -- The distinction the `Result` has to keep: an echo of rows the
                -- model already holds is the common case, not a failure.
                Data.cardDataReceived (encodeRows [ syncedRow { id = "a", parentId = Nothing, position = 1, content = "Root", ts = 1000 } ])
                    ( Data.model_tests_only [ syncedRow { id = "a", parentId = Nothing, position = 1, content = "Root", ts = 1000 } ] Nothing
                    , Tree "0" "" (Children [ Tree "a" "Root" (Children []) ])
                    , "tree1"
                    )
                    |> Expect.equal (Ok Nothing)
        , test "a push acknowledgement that does not parse reports the reason and the values" <|
            \_ ->
                Data.model_tests_only
                    [ unsyncedRow { id = "a", parentId = Nothing, position = 1, content = "Root", ts = 2000 } ]
                    Nothing
                    |> Data.pushOkHandler "tree1" [ "not-a-stamp" ]
                    |> Result.mapError (\err -> ( String.contains "UpdatedAt" err, String.contains "not-a-stamp" err ))
                    |> Expect.equal (Err ( True, True ))
        , test "history that does not decode reports the reason instead of the model back" <|
            \_ ->
                Data.model_tests_only [ syncedRow { id = "a", parentId = Nothing, position = 1, content = "Root", ts = 1000 } ] Nothing
                    |> Data.historyReceived
                        (Enc.list identity
                            [ Enc.object
                                [ ( "snapshot", Enc.string snapshotId )

                                -- No `ts`: the snapshot's timestamp is what the
                                -- history slider orders by.
                                , ( "data", encodeRows [] )
                                ]
                            ]
                        )
                    |> Result.mapError (String.contains "ts")
                    |> Expect.equal (Err True)
        ]


{-| What `cardDataReceived` answered, for a failure message.
-}
describeReceived : Result String (Maybe a) -> String
describeReceived received =
    case received of
        Ok Nothing ->
            "no change"

        Ok (Just _) ->
            "a change"

        Err err ->
            "the error " ++ err
