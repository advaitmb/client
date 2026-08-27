module ViewModeTest exposing (fullscreenOnABlockedDocument, splittingACardOnABlockedDocument)

{-| Tests at the ADR-0001 seam 11: which mode a document is in after an event,
and what the event leaves in its cards.

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

The second suite is ticket 24's, and reads the *cards* rather than the mode.
`mod+j` / `mod+k` / `mod+l` split the open card at the cursor, and they used to
write the truncated half into the working tree *before* calling `insert` — so
`insert`'s guard took the already-mutated model for its "original", and a blocked
document kept the truncation while refusing the card (ticket 31's Comments). The
guard has to see the model as the keystroke found it.

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
import Types exposing (Children(..), CursorPosition(..), Tree, ViewMode(..))


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



-- === SPLITTING A CARD (ticket 24) ===


{-| The editor open on the first card, with the cursor reported between "First"
and " card" -- as `gw-textarea` reports it on every keystroke and click.
-}
editingMidWord : Page.Doc.Model
editingMidWord =
    editing
        |> fromOutside
            (Incoming.TextCursor
                { selected = False, position = Other, text = ( "First", " card" ) }
            )


{-| The same, in the fullscreen editor. -}
fullscreenMidWord : Page.Doc.Model
fullscreenMidWord =
    inFullscreen
        |> fromOutside
            (Incoming.TextCursor
                { selected = False, position = Other, text = ( "First", " card" ) }
            )


{-| Every card of the document, id and content, in tree order. What a split
leaves behind is the whole point, so they are compared as a list rather than one
card at a time.
-}
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


{-| The cards a split leaves, with any newly inserted one shown as "(new)" --
its id is a random string, and what matters is where it is and what is in it.
-}
cardsWithNewOne : Page.Doc.Model -> List ( String, String )
cardsWithNewOne model =
    cards model
        |> List.map
            (\( id, content ) ->
                if List.member id [ "1", "2" ] then
                    ( id, content )

                else
                    ( "(new)", content )
            )


splittingACardOnABlockedDocument : Test
splittingACardOnABlockedDocument =
    describe "A blocked document asked to split the card being edited"
        [ test "leaves the card whole when mod+j is refused" <|
            \_ ->
                editingMidWord
                    |> blocked
                    |> fromOutside (Incoming.Keyboard "mod+j")
                    |> cards
                    |> Expect.equal [ ( "1", "First card" ), ( "2", "Second card" ) ]
        , test "leaves the card whole when mod+k is refused" <|
            \_ ->
                editingMidWord
                    |> blocked
                    |> fromOutside (Incoming.Keyboard "mod+k")
                    |> cards
                    |> Expect.equal [ ( "1", "First card" ), ( "2", "Second card" ) ]
        , test "leaves the card whole when mod+l is refused" <|
            \_ ->
                editingMidWord
                    |> blocked
                    |> fromOutside (Incoming.Keyboard "mod+l")
                    |> cards
                    |> Expect.equal [ ( "1", "First card" ), ( "2", "Second card" ) ]
        , test "leaves the card whole in a fullscreen editor too" <|
            \_ ->
                fullscreenMidWord
                    |> blocked
                    |> fromOutside (Incoming.Keyboard "mod+j")
                    |> cards
                    |> Expect.equal [ ( "1", "First card" ), ( "2", "Second card" ) ]
        , test "mod+j splits the card in two when nothing is blocked" <|
            \_ ->
                editingMidWord
                    |> fromOutside (Incoming.Keyboard "mod+j")
                    |> cardsWithNewOne
                    |> Expect.equal
                        [ ( "1", "First" ), ( "(new)", " card" ), ( "2", "Second card" ) ]
        , test "mod+k puts the text before the cursor in a card above" <|
            \_ ->
                editingMidWord
                    |> fromOutside (Incoming.Keyboard "mod+k")
                    |> cardsWithNewOne
                    |> Expect.equal
                        [ ( "(new)", "First" ), ( "1", " card" ), ( "2", "Second card" ) ]
        , test "mod+l puts the text after the cursor in a new child" <|
            \_ ->
                editingMidWord
                    |> fromOutside (Incoming.Keyboard "mod+l")
                    |> cardsWithNewOne
                    |> Expect.equal
                        [ ( "1", "First" ), ( "(new)", " card" ), ( "2", "Second card" ) ]
        , test "mod+j splits the card in a fullscreen editor as well" <|
            \_ ->
                fullscreenMidWord
                    |> fromOutside (Incoming.Keyboard "mod+j")
                    |> cardsWithNewOne
                    |> Expect.equal
                        [ ( "1", "First" ), ( "(new)", " card" ), ( "2", "Second card" ) ]
        ]
