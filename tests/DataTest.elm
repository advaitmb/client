module DataTest exposing (suite)

{-| Tests at ADR-0001 seam 1: the `Doc.Data` public API.

`localSave` is asserted through the JSON it hands the port layer (the
`DBChangeLists` shape `src/shared/doc.js` persists to Dexie), decoded
field-by-field rather than compared as a string, because the field names
are the contract and the key order is not.

-}

import Doc.Data as Data
import Expect
import Json.Decode as Dec
import Test exposing (Test, describe, test)
import Types exposing (CardTreeOp(..), Children(..), Tree)
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
    , toRemove : List Dec.Value
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
        (Dec.field "toRemove" (Dec.list Dec.value))


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
        ]
