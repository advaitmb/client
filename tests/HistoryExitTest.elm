module HistoryExitTest exposing (leavingTheHistoryView)

{-| Tests at the ADR-0001 seam 11: what an event leaves in the document —
here, the event being one of the three ways out of the history view.

Moving the slider is a **checkout**: the version you picked goes into the
working tree so you can read it, and editing is blocked while it is there.
Leaving the view is the decision this file is about. `CancelHistory` (the ✕)
put the tree back to the version the view opened at; closing the same view from
the header's history icon (`HistoryToggled False`) only dropped the menu, so the
old version stayed in the working tree — unblocked, and one keystroke from being
saved over the document. Ticket 33 made the icon keyboard-reachable and turned
that into the obvious exit; ticket 34 makes every exit that commits nothing put
the document back, which is what leaving a preview means.

`Page.App.Model` carries a `Nav.Key` no test can make (ADR-0001 seam 5), so the
decision is a function of the two things that are plain data — the history and
the document — and `update` is left with putting the answer back and dropping
the menu. The exit is named after the control that asked for it, because "which
of these three keeps the version on screen" is the whole question: with the
answer at the call sites they disagreed, and nothing could see it.

What the tests read is the working tree, and then the mode a following
keystroke leaves: the block goes with the view, so a closed history view is a
document you can type in again — on the version the exit chose.

-}

import Doc.Data as Data
import Doc.History as History
import Expect
import GlobalData
import Json.Encode as Enc
import Page.App
import Page.Doc
import Page.Doc.Incoming as Incoming
import Test exposing (Test, describe, test)
import Types exposing (Children(..), Tree, ViewMode(..))


{-| The document as it stands now — what the working tree holds when the
history view opens, and what every exit but a restore has to leave behind.
-}
current : Tree
current =
    Tree "0" "" (Children [ Tree "1" "Today's card" (Children []) ])


snapshotId : String
snapshotId =
    "snapshot-1"


{-| The one saved version, as `src/shared/doc.js` hands history to Elm: a
snapshot id, when it was taken, and the card rows that were alive then.
-}
snapshots : Enc.Value
snapshots =
    Enc.list identity
        [ Enc.object
            [ ( "snapshot", Enc.string snapshotId )
            , ( "ts", Enc.int 1000 )
            , ( "data"
              , Enc.list identity
                    [ Enc.object
                        [ ( "id", Enc.string "1" )
                        , ( "treeId", Enc.string "tree1" )
                        , ( "content", Enc.string "Yesterday's card" )
                        , ( "parentId", Enc.null )
                        , ( "position", Enc.float 1 )
                        , ( "deleted", Enc.int 0 )
                        , ( "synced", Enc.bool True )
                        , ( "updatedAt", Enc.string "1000:0:hash-1-1000" )
                        ]
                    ]
              )
            ]
        ]


{-| The document's stored data with that one version in its history.
-}
data : Data.Model
data =
    Data.emptyCardBased
        |> Data.historyReceived snapshots
        |> Result.withDefault Data.emptyCardBased


{-| The history view with its one old version checked out, and the document as
`Page.App` leaves it while that version is on screen: the snapshot in the
working tree, editing blocked.

A `Result` rather than a `Maybe` unwrapped with a default, so that a fixture
that stops producing a version says so instead of quietly testing an empty
history (`revert Empty` is `Nothing`, which every exit would then agree on).

-}
viewingAnOldVersion : Result String ( History.History, Page.Doc.Model )
viewingAnOldVersion =
    case History.checkoutVersion snapshotId (History.init current data) of
        Just ( history, checkedOutTree ) ->
            Ok
                ( history
                , Page.Doc.init False GlobalData.public
                    |> withTree current
                    |> Page.Doc.setLoading False
                    |> withTree checkedOutTree
                    |> Page.Doc.setBlock (Just "Cannot edit while viewing history.")
                )

        Nothing ->
            Err ("the fixture's history has no version " ++ snapshotId ++ " to check out")


withTree : Tree -> Page.Doc.Model -> Page.Doc.Model
withTree tree model =
    Page.Doc.setTree tree model |> (\( m, _, _ ) -> m)


{-| Every card of the document the exit leaves, id and content, in tree order.
-}
cardsAfter : Page.App.HistoryExit -> Result String (List ( String, String ))
cardsAfter exit =
    viewingAnOldVersion
        |> Result.map (closeWith exit >> cards)


{-| The mode the document is left in when the card is opened for editing after
the exit — and so both halves of "editing is possible again": that the block
went with the view, and which version the editor opens on.
-}
modeAfter : Page.App.HistoryExit -> Result String ViewMode
modeAfter exit =
    viewingAnOldVersion
        |> Result.map
            (closeWith exit
                >> Page.Doc.opaqueIncoming (Incoming.Keyboard "enter")
                >> (\( m, _, _ ) -> Page.Doc.getViewMode m)
            )


closeWith : Page.App.HistoryExit -> ( History.History, Page.Doc.Model ) -> Page.Doc.Model
closeWith exit ( history, docModel ) =
    Page.App.closeHistoryView exit history docModel |> Tuple.first


cards : Page.Doc.Model -> List ( String, String )
cards model =
    Page.Doc.getWorkingTree model
        |> .tree
        |> preorder
        |> List.filter (\( id, _ ) -> id /= "0")


preorder : Tree -> List ( String, String )
preorder tree =
    case tree.children of
        Children children ->
            ( tree.id, tree.content ) :: List.concatMap preorder children


leavingTheHistoryView : Test
leavingTheHistoryView =
    describe "Leaving the history view with an old version checked out"
        [ test "the header's history icon puts the document back where the view opened" <|
            \_ ->
                cardsAfter Page.App.HistoryIcon
                    |> Expect.equal (Ok [ ( "1", "Today's card" ) ])
        , test "the menu's cancel button puts it back as well" <|
            \_ ->
                cardsAfter Page.App.CancelButton
                    |> Expect.equal (Ok [ ( "1", "Today's card" ) ])
        , test "a restore keeps the version that is on screen" <|
            \_ ->
                -- The version being committed. Putting the original back here
                -- would undo the restore the user just asked for.
                cardsAfter Page.App.RestoreButton
                    |> Expect.equal (Ok [ ( "1", "Yesterday's card" ) ])
        , test "closing from the icon leaves a document that can be edited again" <|
            \_ ->
                modeAfter Page.App.HistoryIcon
                    |> Expect.equal (Ok (Editing { cardId = "1", field = "Today's card" }))
        , test "closing from the cancel button does too" <|
            \_ ->
                modeAfter Page.App.CancelButton
                    |> Expect.equal (Ok (Editing { cardId = "1", field = "Today's card" }))
        , test "a restore leaves the restored version editable" <|
            \_ ->
                modeAfter Page.App.RestoreButton
                    |> Expect.equal (Ok (Editing { cardId = "1", field = "Yesterday's card" }))
        ]
