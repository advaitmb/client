module Utils exposing (asButton, delay, emptyText, getFieldErrors, gravatar, hash, onClickStop, ternary, text, textNoTr)

{--import DebugToJson exposing (pp)--}

import Hex
import Html exposing (Html)
import Html.Attributes exposing (attribute)
import Html.Events exposing (custom, onClick, stopPropagationOn)
import Json.Decode as Dec
import Murmur3 exposing (hashString)
import Process
import Task
import Translation exposing (TranslationId, tr)


ternary : Bool -> a -> a -> a
ternary condition trueValue falseValue =
    if condition then
        trueValue

    else
        falseValue


onClickStop : msg -> Html.Attribute msg
onClickStop msg =
    stopPropagationOn "click" (Dec.succeed ( msg, True ))


{-| What makes an element that cannot *be* a `<button>` behave like one:
reachable with Tab, announced as a button, and activated by Enter or Space (S12
— a clickable `div` is none of those).

Use a real `<button>` wherever the content allows it. This exists for the
breadcrumbs, whose label is rendered markdown and so may contain a link, which a
`<button>` may not contain.

The keydown is `stopPropagation`ed because the app's global shortcuts are bound
on `document` by Mousetrap, which only ignores keystrokes inside form fields: a
focused `div` is not one, so Enter would both activate this element and fire the
global `enter` shortcut (opening the active card's editor). Space is
`preventDefault`ed, or activating scrolls the page as well.

-}
asButton : msg -> List (Html.Attribute msg)
asButton msg =
    [ attribute "role" "button"
    , attribute "tabindex" "0"
    , onClick msg
    , custom "keydown" (activationKey msg)
    ]


activationKey : msg -> Dec.Decoder { message : msg, stopPropagation : Bool, preventDefault : Bool }
activationKey msg =
    Dec.field "key" Dec.string
        |> Dec.andThen
            (\key ->
                case key of
                    "Enter" ->
                        Dec.succeed { message = msg, stopPropagation = True, preventDefault = False }

                    " " ->
                        Dec.succeed { message = msg, stopPropagation = True, preventDefault = True }

                    _ ->
                        -- Every other key: no message, and nothing prevented or
                        -- stopped, so the global shortcuts still see it.
                        Dec.fail "not an activation key"
            )


hash : Int -> String -> String
hash seed str =
    hashString seed str
        |> Hex.toString


delay : Int -> msg -> Cmd msg
delay ms msg =
    Task.perform (always msg) (Process.sleep <| toFloat ms)


gravatar : Int -> String -> String
gravatar _ _ =
    -- Self-host: upstream hashed the account email and fetched an avatar from
    -- gravatar.com, sending a hash of the address to a third party on every
    -- render (this helper also feeds the collaborators UI in the header, so it
    -- fired even with no collaborators). Serve a local icon instead.
    "/leaf128.png"


-- Debugging


text : TranslationId -> Html msg
text tid =
    Html.text <| tr tid


textNoTr : String -> Html msg
textNoTr str =
    Html.text str


emptyText : Html msg
emptyText =
    Html.text ""


getFieldErrors : field -> List ( field, a ) -> List a
getFieldErrors field errs =
    errs
        |> List.filter ((==) field << Tuple.first)
        |> List.map Tuple.second
