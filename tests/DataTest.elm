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

import Doc.Data as Data
import Expect
import Json.Decode as Dec
import Json.Encode as Enc
import Outgoing
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
snapshot from `deleted: 0` rows only and forces `deleted = 0` on every row it
passes on, so a deleted card is simply absent from a snapshot.
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
    { toAdd : List StagedRow
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


changeListsDecoder : Dec.Decoder ChangeLists
changeListsDecoder =
    Dec.map4 ChangeLists
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
        Nothing ->
            Err "expected cardDataReceived to report the received rows"

        Just { newData } ->
            if not (Data.hasConflicts newData) then
                Err "expected the offline edits to be reported as a conflict for the user to resolve"

            else
                case
                    Data.resolveConflicts selection newData
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
rowsNow : List (Data.Card_tests_only UpdatedAt)
rowsNow =
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


{-| The save `restore` stages for that snapshot, decoded.
-}
restoreChanges : Result String ChangeLists
restoreChanges =
    Data.model_tests_only rowsNow Nothing
        |> Data.historyReceived (encodeHistory [ ( snapshotId, 2000, snapshotRows ) ])
        |> (\model -> Data.restore model snapshotId)
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
                        applySave 6000 changes rowsNow
                in
                case Data.cardDataReceived (encodeRows rowsAfter) ( Data.emptyCardBased, Tree "0" "" (Children []), "tree1" ) of
                    Nothing ->
                        Err "expected cardDataReceived to report the restored rows"

                    Just { newTree, outMsg } ->
                        pushedDeltas outMsg
                            |> Result.map (\pushed -> { tree = newTree, pushed = pushed })
            )


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
                in
                Dec.decodeValue changeListsDecoder saved
                    |> Expect.equal
                        (Ok
                            { toAdd =
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
                in
                Dec.decodeValue changeListsDecoder saved
                    |> Expect.equal
                        (Ok
                            { toAdd =
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
                in
                Dec.decodeValue changeListsDecoder saved
                    |> Expect.equal
                        (Ok
                            { toAdd = []
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
                in
                Dec.decodeValue changeListsDecoder saved
                    |> Expect.equal
                        (Ok
                            { toAdd =
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
                    Nothing ->
                        Expect.fail "expected cardDataReceived to report the conflict resolution"

                    Just { newData, outMsg } ->
                        ( outMsg |> savePayload |> Maybe.map (Dec.decodeValue changeListsDecoder)
                        , Data.hasConflicts newData
                        )
                            |> Expect.equal
                                ( Just
                                    (Ok
                                        { toAdd = []
                                        , toMarkSynced = []
                                        , toMarkDeleted = []
                                        , toRemove = [ "1000:0:orig" ]
                                        }
                                    )
                                , False
                                )
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
                                { toAdd = []
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
                                { toAdd =
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
                                { toAdd = []
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
                            { toAdd =
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
        ]
