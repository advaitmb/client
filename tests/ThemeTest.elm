module ThemeTest exposing (appliedTheme, restoredTheme)

{-| Tests at the ADR-0001 seam 10: the per-document theme, which is saved on
change and — until now — never read back (E10).

The write and the read are two halves of one round trip. `SaveThemeSetting`
sends `Theme.toValue`, which `doc.js` puts in the document's localStore
(`gingko-local-store/<treeId>/settings`); on the next document load that whole
blob rides along with the card rows, in the same place `last-actives` does.
`Page.App` had no reader, so every reload started at `Default`.

`Page.App.cardDataReceived` itself is untestable (it needs a
`Browser.Navigation.Key`), so the decision is `Theme.fromLocalStore`: the
theme a card-data message names, or the one already in effect.

-}

import Expect
import Html
import Json.Encode as Enc
import Page.Doc.Theme as Theme exposing (Theme(..))
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector


{-| Every theme, with the class `applyTheme` marks the document root with.
`Default` is the unstyled one: it adds no class at all.
-}
themes : List ( Theme, String )
themes =
    [ ( Default, "" )
    , ( Classic, "classic-theme" )
    , ( Gray, "gray-theme" )
    , ( Green, "green-theme" )
    , ( Turquoise, "turquoise-theme" )
    , ( Dark, "dark-theme" )
    ]


{-| A card-data message with the document's localStore attached, as
`loadCardBasedDocument` sends it on a document load. The real message is the
array of card rows *with* a `localStore` property, which Elm's `field` decoder
reads exactly like the object below.
-}
cardDataWith : List ( String, Enc.Value ) -> Enc.Value
cardDataWith store =
    Enc.object [ ( "localStore", Enc.object store ) ]


restoredTheme : Test
restoredTheme =
    describe "the theme a card-data message restores"
        (test "a document whose theme was never set keeps the default"
            (\_ ->
                cardDataWith [ ( "last-actives", Enc.list Enc.string [ "abc" ] ) ]
                    |> Theme.fromLocalStore Default
                    |> Expect.equal Default
            )
            :: test "a message with no localStore leaves the theme alone"
                (\_ ->
                    -- Every liveQuery echo after the first: card rows only.
                    Enc.list Enc.string []
                        |> Theme.fromLocalStore Dark
                        |> Expect.equal Dark
                )
            :: test "a stored theme this build does not know is the default"
                (\_ ->
                    cardDataWith [ ( "theme", Enc.string "aubergine" ) ]
                        |> Theme.fromLocalStore Dark
                        |> Expect.equal Default
                )
            :: List.map
                (\( theme, _ ) ->
                    test ("a saved " ++ Debug.toString theme ++ " theme survives a reload")
                        (\_ ->
                            -- Exactly the value SaveThemeSetting stored, in
                            -- exactly the place doc.js stored it.
                            cardDataWith [ ( "theme", Theme.toValue theme ) ]
                                |> Theme.fromLocalStore Default
                                |> Expect.equal theme
                        )
                )
                themes
        )


appliedTheme : Test
appliedTheme =
    describe "the class a restored theme puts on the document"
        (List.map
            (\( theme, className ) ->
                test (Debug.toString theme ++ " marks the document root")
                    (\_ ->
                        let
                            root =
                                Html.div [ Theme.applyTheme theme ] []
                                    |> Query.fromHtml

                            others =
                                themes
                                    |> List.map Tuple.second
                                    |> List.filter (\c -> c /= "" && c /= className)
                        in
                        root
                            |> Expect.all
                                ((if className == "" then
                                    []

                                  else
                                    [ Query.has [ Selector.class className ] ]
                                 )
                                    ++ List.map
                                        (\c -> Query.hasNot [ Selector.class c ])
                                        others
                                )
                    )
            )
            themes
        )
