module IncomingTest exposing (everyTagTheDocSends, fullscreenChanged)

{-| Tests at the ADR-0001 seam 10: the port tag → `Msg` mapping.

`src/shared/doc.js` sends the document's inbound messages as
`{ tag, data }` pairs on one port. `Page.Doc.Incoming.subscribe` used to hold
both halves of the answer -- which tag means what, and what to do with a tag
nobody knows -- inside the subscription's callback, where no test can reach it:
a `Sub msg` cannot be run. `fromOutside` is that decision on its own, so this
file can ask it what the JS side's messages mean.

What it pins: `FullscreenChanged` had no branch at all, so screenfull's change
event (doc.js's `screenfull.on('change', …)`) reached Elm as an unknown tag and
was logged instead of leaving fullscreen editing -- Esc could not exit (E6).
A tag missing here is invisible in any other way: the app keeps running and
writes a console line.

-}

import Expect
import Json.Encode as Enc
import Page.Doc.Incoming as Incoming exposing (Msg(..))
import Test exposing (Test, describe, test)


{-| A message as `doc.js`'s `toElm(data, 'docMsgs', tag)` builds it.
-}
fromJs : String -> Enc.Value -> Result String Msg
fromJs tag data =
    Incoming.fromOutside { tag = tag, data = data }


fullscreenChanged : Test
fullscreenChanged =
    describe "The browser's fullscreen state changing"
        [ test "is understood when fullscreen was left" <|
            \_ ->
                fromJs "FullscreenChanged" (Enc.bool False)
                    |> Expect.equal (Ok (FullscreenChanged False))
        , test "is understood when fullscreen was entered" <|
            \_ ->
                fromJs "FullscreenChanged" (Enc.bool True)
                    |> Expect.equal (Ok (FullscreenChanged True))
        , test "is an error when the payload is not a boolean" <|
            \_ ->
                fromJs "FullscreenChanged" Enc.null
                    |> Result.toMaybe
                    |> Expect.equal Nothing
        ]


everyTagTheDocSends : Test
everyTagTheDocSends =
    describe "A tag from outside"
        [ test "that nobody knows is an error naming it" <|
            \_ ->
                fromJs "SomethingNobodyHandles" Enc.null
                    |> Expect.equal (Err "Unexpected info from outside: SomethingNobodyHandles")
        , test "that carries no payload needs none" <|
            \_ ->
                fromJs "ClickedOutsideCard" Enc.null
                    |> Expect.equal (Ok ClickedOutsideCard)
        , test "that carries a payload decodes it" <|
            \_ ->
                fromJs "FieldChanged" (Enc.string "the card's new text")
                    |> Expect.equal (Ok (FieldChanged "the card's new text"))
        , test "that carries the wrong payload is an error, not a message" <|
            \_ ->
                fromJs "FieldChanged" (Enc.int 7)
                    |> Result.toMaybe
                    |> Expect.equal Nothing
        ]
