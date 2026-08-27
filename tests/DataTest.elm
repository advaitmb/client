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
        ]
