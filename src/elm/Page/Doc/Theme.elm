module Page.Doc.Theme exposing (Theme(..), applyTheme, fromLocalStore, fromName, name, toValue)

import Html
import Html.Attributes exposing (class)
import Json.Decode as Dec exposing (Decoder)
import Json.Encode as Enc


type Theme
    = Default
    | Classic
    | Gray
    | Green
    | Turquoise
    | Dark


applyTheme : Theme -> Html.Attribute msg
applyTheme theme =
    case theme of
        Default ->
            class ""

        Classic ->
            class "classic-theme"

        Gray ->
            class "gray-theme"

        Green ->
            class "green-theme"

        Turquoise ->
            class "turquoise-theme"

        Dark ->
            class "dark-theme"


{-| The name a theme travels under: what `SaveThemeSetting` stores, what the
`theme` attribute tells `<gw-header>`, and what its picker reports back. One
spelling, so a theme chosen in the menu is the theme the next load restores.
-}
name : Theme -> String
name theme =
    case theme of
        Default ->
            "default"

        Classic ->
            "classic"

        Gray ->
            "gray"

        Green ->
            "green"

        Turquoise ->
            "turquoise"

        Dark ->
            "dark"


{-| The theme a name means, and `Default` for one this build does not know —
an attribute, an event detail and a stored setting are all strings from
outside, so this has to be total.
-}
fromName : String -> Theme
fromName themeName =
    case themeName of
        "classic" ->
            Classic

        "gray" ->
            Gray

        "green" ->
            Green

        "turquoise" ->
            Turquoise

        "dark" ->
            Dark

        _ ->
            Default


toValue : Theme -> Enc.Value
toValue =
    name >> Enc.string


{-| The theme a card-data message names, or the one already in effect.

A document load attaches the document's localStore blob to the card rows
(`doc.js`'s `loadCardBasedDocument`, the same ride `last-actives` takes), and
that blob is where `SaveThemeSetting` put `toValue`'s string. Nothing else
carries one: the liveQuery echoes that follow are card rows alone, and a
document whose theme was never set has no `theme` key, so anything this cannot
read leaves the current theme alone.

-}
fromLocalStore : Theme -> Dec.Value -> Theme
fromLocalStore current cardData =
    Dec.decodeValue (Dec.field "localStore" decoder) cardData
        |> Result.withDefault current


decoder : Decoder Theme
decoder =
    Dec.field "theme" Dec.string
        |> Dec.map fromName
