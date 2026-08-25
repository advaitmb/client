module Utils exposing (delay, emptyText, getFieldErrors, gravatar, hash, hexEncode, myDebug, onClickStop, onClickStopStyled, ternary, text, textElmCss, textNoTr, voxEmporiumHash)

{--import DebugToJson exposing (pp)--}

import Hex
import Html exposing (Html)
import Html.Events exposing (stopPropagationOn)
import Html.Styled
import Html.Styled.Events
import Json.Decode as Dec
import Murmur3 exposing (hashString)
import Process
import SHA256
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


onClickStopStyled : msg -> Html.Styled.Attribute msg
onClickStopStyled msg =
    Html.Styled.Events.stopPropagationOn "click" (Dec.succeed ( msg, True ))


hexEncode : String -> String
hexEncode input =
    input
        |> String.toList
        |> List.map Char.toCode
        |> List.map Hex.toString
        |> String.join ""


hash : Int -> String -> String
hash seed str =
    hashString seed str
        |> Hex.toString


voxEmporiumHash : String -> String
voxEmporiumHash rawEmail =
    (rawEmail ++ "{%VOX_EMPORIUM_SALT%}")
        |> String.toLower
        |> String.trim
        |> SHA256.fromString
        |> SHA256.toHex
        |> String.left 16


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


myDebug : String -> a -> a
myDebug label value =
    let
        _ =
            --Debug.log label (pp (Debug.toString value))
            ()
    in
    value



-- Translation Helper Function


text : TranslationId -> Html msg
text tid =
    Html.text <| tr tid


textElmCss : TranslationId -> Html.Styled.Html msg
textElmCss tid =
    Html.Styled.text <| tr tid


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
