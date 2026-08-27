module Page.Doc.Theme exposing (Theme(..), applyTheme, fromLocalStore, toValue)

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


toValue : Theme -> Enc.Value
toValue theme =
    case theme of
        Default ->
            Enc.string "default"

        Classic ->
            Enc.string "classic"

        Gray ->
            Enc.string "gray"

        Green ->
            Enc.string "green"

        Turquoise ->
            Enc.string "turquoise"

        Dark ->
            Enc.string "dark"


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
        |> Dec.map
            (\s ->
                case s of
                    "default" ->
                        Default

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
            )
