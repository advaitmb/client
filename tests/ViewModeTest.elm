module ViewModeTest exposing (fullscreenOnABlockedDocument)

{-| Tests at the ADR-0001 seam 11: which mode a document is in after an event.

A blocked document -- one being read in the history view, or a public document
someone else owns -- may not be edited: `Page.Doc.preventIfBlocked` answers
every editing transition with the block's alert and the model it started from.
`changeMode`'s three `FullscreenEditing` targets carried no guard at all, so
`shift+enter` on a blocked document really opened a fullscreen editor (and told
collaborators the card was being edited).

Every way into a fullscreen editor, and where each is tested below: from the
normal view, `shift+enter`; from the normal editor, the card editor's
fullscreen button (`gw-edit-fullscreen`); from a fullscreen editor onto another
card, the fullscreen view reporting the focus move
(`FullscreenCardFocused`). Inserting a card from a fullscreen editor is the
fourth, and it is guarded by `insert` itself rather than by `changeMode`.

What a test can see here is the mode: `Page.Doc.update` answers in `Cmd`s no
test can inspect (ADR-0001 seam 10 records that), but the mode the document is
left in is plain data, and a fullscreen editor that never opens is exactly what
this ticket is about.

-}

import Expect
import GlobalData
import Html
import Json.Encode as Enc
import Page.Doc
import Page.Doc.Incoming as Incoming
import Test exposing (Test, describe, test)
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import Types exposing (Children(..), Tree, ViewMode(..))


{-| A two-card document as it comes back from storage.
-}
doc : Tree
doc =
    Tree "0"
        ""
        (Children
            [ Tree "1" "First card" (Children [])
            , Tree "2" "Second card" (Children [])
            ]
        )


{-| The document open on screen, first card active, editable.
-}
opened : Page.Doc.Model
opened =
    Page.Doc.init False GlobalData.public
        |> Page.Doc.setTree doc
        |> (\( model, _, _ ) -> model)
        |> Page.Doc.setLoading False


{-| The same document with editing blocked, as `Page.App` leaves it when the
history view opens.
-}
blocked : Page.Doc.Model -> Page.Doc.Model
blocked =
    Page.Doc.setBlock (Just "Cannot edit while viewing history.")


{-| One message from the port layer, delivered to the document.
-}
fromOutside : Incoming.Msg -> Page.Doc.Model -> Page.Doc.Model
fromOutside msg model =
    Page.Doc.opaqueIncoming msg model
        |> (\( newModel, _, _ ) -> newModel)


{-| The document with its first card open in the fullscreen editor, reached the
way a reader reaches it: `shift+enter` while nothing is blocked.
-}
inFullscreen : Page.Doc.Model
inFullscreen =
    opened
        |> fromOutside (Incoming.Keyboard "shift+enter")


{-| The document with its first card open in the normal editor. Opened before
any block, because that is the only way an editor is ever open on a document
that is blocked: the block arrives while it is.
-}
editing : Page.Doc.Model
editing =
    opened
        |> fromOutside (Incoming.Keyboard "enter")


{-| `Page.Doc.Msg` has no exported constructors, so the only way to ask the
document for the third fullscreen-entering transition -- from the normal editor
-- is the event that asks for it in the app: `<gw-tree>`'s
`gw-edit-fullscreen`, dispatched by the card editor's fullscreen button.
-}
type TestMsg
    = DocMsg Page.Doc.Msg
    | SomeOtherMsg


docView : Page.Doc.Model -> Html.Html TestMsg
docView model =
    Html.div []
        (Page.Doc.view
            { docMsg = DocMsg
            , keyboard = \_ -> SomeOtherMsg
            , tooltipRequested = \_ _ _ -> SomeOtherMsg
            , tooltipClosed = SomeOtherMsg
            }
            Nothing
            Nothing
            model
        )


{-| The mode the document is left in when the card editor's fullscreen button
is pressed, or why the press could not be delivered.
-}
modeAfterFullscreenButton : Page.Doc.Model -> Result String ViewMode
modeAfterFullscreenButton model =
    docView model
        |> Query.fromHtml
        |> Query.find [ Selector.tag "gw-tree" ]
        |> Event.simulate (Event.custom "gw-edit-fullscreen" (Enc.object []))
        |> Event.toResult
        |> Result.andThen
            (\msg ->
                case msg of
                    DocMsg docMsg ->
                        Page.Doc.opaqueUpdate docMsg model
                            |> (\( newModel, _, _ ) -> Ok (Page.Doc.getViewMode newModel))

                    SomeOtherMsg ->
                        Err "gw-edit-fullscreen asked for something other than the document's own message"
            )


fullscreenOnABlockedDocument : Test
fullscreenOnABlockedDocument =
    describe "A blocked document asked for a fullscreen editor"
        [ test "stays in normal mode on shift+enter" <|
            \_ ->
                opened
                    |> blocked
                    |> fromOutside (Incoming.Keyboard "shift+enter")
                    |> Page.Doc.getViewMode
                    |> Expect.equal (Normal "1")
        , test "opens the fullscreen editor when nothing is blocked" <|
            \_ ->
                opened
                    |> fromOutside (Incoming.Keyboard "shift+enter")
                    |> Page.Doc.getViewMode
                    |> Expect.equal (FullscreenEditing { cardId = "1", field = "First card" })
        , test "does not follow the fullscreen view's focus to another card" <|
            \_ ->
                inFullscreen
                    |> blocked
                    |> fromOutside (Incoming.FullscreenCardFocused "2" "Second card")
                    |> Page.Doc.getViewMode
                    |> Expect.equal (FullscreenEditing { cardId = "1", field = "First card" })
        , test "follows that focus when nothing is blocked" <|
            \_ ->
                inFullscreen
                    |> fromOutside (Incoming.FullscreenCardFocused "2" "Second card")
                    |> Page.Doc.getViewMode
                    |> Expect.equal (FullscreenEditing { cardId = "2", field = "Second card" })
        , test "leaves the card editor where it is when the fullscreen button is pressed" <|
            \_ ->
                editing
                    |> blocked
                    |> modeAfterFullscreenButton
                    |> Expect.equal (Ok (Editing { cardId = "1", field = "First card" }))
        , test "goes fullscreen from that button when nothing is blocked" <|
            \_ ->
                editing
                    |> modeAfterFullscreenButton
                    |> Expect.equal (Ok (FullscreenEditing { cardId = "1", field = "First card" }))
        ]
