module ChromeTest exposing (breadcrumbs, emptyDocumentScreen)

{-| Tests at the ADR-0001 seam 10: what the document's chrome says and writes —
here, what it can be *operated with*.

Both subjects were clickable `div`s that no keyboard could reach (CODE_REVIEW.md
S12). A mouse-only control is invisible to a keyboard user and to anything
driving the app through the accessibility tree, and nothing noticed: a view that
reports nothing looks exactly like a view that was never touched.

The empty-documents screen is also checked for what is *not* there any more: it
used to fire a message from a broken `<img>`'s error event, as a way of getting
a callback out of a view.

The show/hide-password buttons on the login and signup forms are the same fix
and are not here: those views take a page `Model`, which carries a `Nav.Key` no
test can make (the reason seams 5, 7-10 exist). They are verified by inspection.

-}

import Doc.UI as UI
import Expect
import Html
import Html.Attributes as Attributes
import Json.Encode as Enc
import Page.DocMessage
import Test exposing (Test, describe, test)
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector as Selector


{-| What a crumb or the new-document button asks for. -}
type Msg
    = CrumbClicked String
    | NewDocumentClicked


{-| The breadcrumb trail for a card three deep. -}
crumbs : Query.Single Msg
crumbs =
    UI.viewBreadcrumbs CrumbClicked
        [ ( "card-1", "The root card" )
        , ( "card-2", "A middle card" )
        , ( "card-3", "The card in view" )
        ]
        |> Query.fromHtml


{-| The crumb for `card-2`: not the first or the last, so a test that finds the
wrong one says so.
-}
middleCrumb : Query.Single Msg
middleCrumb =
    crumbs
        |> Query.findAll [ Selector.attribute (Attributes.attribute "role" "button") ]
        |> Query.index 1


{-| A keydown as the browser reports it. -}
keyDown : String -> ( String, Enc.Value )
keyDown key =
    Event.custom "keydown" (Enc.object [ ( "key", Enc.string key ) ])


breadcrumbs : Test
breadcrumbs =
    describe "The breadcrumb trail"
        [ test "every crumb is announced as a button and reachable with Tab" <|
            \_ ->
                crumbs
                    |> Query.findAll
                        [ Selector.attribute (Attributes.attribute "role" "button")
                        , Selector.attribute (Attributes.attribute "tabindex" "0")
                        ]
                    |> Query.count (Expect.equal 3)
        , test "Enter on a crumb goes to that card" <|
            \_ ->
                middleCrumb
                    |> Event.simulate (keyDown "Enter")
                    |> Event.expect (CrumbClicked "card-2")
        , test "Space on a crumb goes to that card" <|
            \_ ->
                middleCrumb
                    |> Event.simulate (keyDown " ")
                    |> Event.expect (CrumbClicked "card-2")
        , test "any other key on a crumb is left to the app's shortcuts" <|
            \_ ->
                middleCrumb
                    |> Event.simulate (keyDown "j")
                    |> Event.toResult
                    |> Expect.err
        , test "clicking a crumb still goes to that card" <|
            \_ ->
                middleCrumb
                    |> Event.simulate Event.click
                    |> Event.expect (CrumbClicked "card-2")
        ]


emptyScreen : Query.Single Msg
emptyScreen =
    Html.div [] (Page.DocMessage.viewEmpty { newClicked = NewDocumentClicked })
        |> Query.fromHtml


emptyDocumentScreen : Test
emptyDocumentScreen =
    describe "The screen for an account with no documents"
        [ test "the new-document control is a real button" <|
            \_ ->
                emptyScreen
                    |> Query.find [ Selector.id "new-button" ]
                    |> Query.has [ Selector.tag "button" ]
        , test "pressing it asks for a new document" <|
            \_ ->
                emptyScreen
                    |> Query.find [ Selector.id "new-button" ]
                    |> Event.simulate Event.click
                    |> Event.expect NewDocumentClicked
        , test "nothing on the screen loads an image, broken or otherwise" <|
            \_ ->
                -- The `<img src="" onerror>` whose failure to load *was* the
                -- message. Its handler in `doc.js` did nothing at all.
                emptyScreen
                    |> Query.findAll [ Selector.tag "img" ]
                    |> Query.count (Expect.equal 0)
        ]
