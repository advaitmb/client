module ThemeTest exposing (appliedTheme, pickedTheme, restoredTheme)

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


{-| The name each theme travels under, in the order the settings menu offers
them. One spelling serves three journeys: the `theme` attribute `<gw-header>`
carries, the detail its picker reports back, and the string `SaveThemeSetting`
has always written into the document's localStore — so a theme chosen in the
menu is the theme a reload restores.
-}
names : List ( Theme, String )
names =
    [ ( Default, "default" )
    , ( Dark, "dark" )
    , ( Classic, "classic" )
    , ( Gray, "gray" )
    , ( Green, "green" )
    , ( Turquoise, "turquoise" )
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


pickedTheme : Test
pickedTheme =
    describe "the theme the settings menu's picker names"
        (test "a name no build of this app ever wrote is the default"
            (\_ ->
                -- The attribute and the detail are strings from outside Elm,
                -- so this has to be total, as the stored name is.
                Theme.fromName "aubergine"
                    |> Expect.equal Default
            )
            :: List.map
                (\( theme, name ) ->
                    test (Debug.toString theme ++ " is offered, chosen and reloaded under one name")
                        (\_ ->
                            Expect.all
                                [ \_ ->
                                    -- What the `theme` attribute says.
                                    Theme.name theme |> Expect.equal name
                                , \_ ->
                                    -- What the picker's `gw-theme` detail means.
                                    Theme.fromName name |> Expect.equal theme
                                , \_ ->
                                    -- And what a reload makes of it, through
                                    -- the store SaveThemeSetting writes.
                                    cardDataWith [ ( "theme", Enc.string (Theme.name theme) ) ]
                                        |> Theme.fromLocalStore Default
                                        |> Expect.equal theme
                                ]
                                ()
                        )
                )
                names
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
