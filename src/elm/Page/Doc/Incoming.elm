port module Page.Doc.Incoming exposing (Msg(..), fromOutside, subscribe)

import Coders exposing (..)
import Json.Decode as Dec exposing (Decoder, decodeValue, errorToString, field)
import Types exposing (Collaborator, CursorPosition(..), OutsideData, TextCursorInfo, Tree)


type
    Msg
    -- === Dialogs, Menus, Window State ===
    = CancelCardConfirmed
      -- === DOM ===
    | InitialActivation String
    | DragExternalStarted
    | DropExternal String
    | Paste Tree
    | PasteInto Tree
    | FieldChanged String
    | AutoSaveRequested
    | FullscreenCardFocused String String
    | FullscreenChanged Bool
    | TextCursor TextCursorInfo
    | ClickedOutsideCard
    | CheckboxClicked String Int
      -- === UI ===
    | Keyboard String
      -- === Misc ===
    | WillPrint
    | RecvCollabState Collaborator
    | RecvCollabUsers (List Collaborator)
    | CollaboratorDisconnected String



-- DECODERS


cursorPositionDecoder : Decoder CursorPosition
cursorPositionDecoder =
    Dec.map
        (\s ->
            case s of
                "start" ->
                    Start

                "end" ->
                    End

                "other" ->
                    Other

                _ ->
                    Other
        )
        Dec.string


textCursorInfoDecoder : Decoder TextCursorInfo
textCursorInfoDecoder =
    Dec.map3 TextCursorInfo
        (field "selected" Dec.bool)
        (field "position" cursorPositionDecoder)
        (field "text" (tupleDecoder Dec.string Dec.string))



-- SUBSCRIPTION HELPER


{-| What a `{ tag, data }` message from `src/shared/doc.js` means.

Total: every tag the JS side sends has a branch, and anything else is an error
naming the tag. Kept out of `subscribe` because a `Sub msg` cannot be run --
this is the half worth testing, and a missing tag is otherwise invisible (the
app logs a line and carries on).

-}
fromOutside : OutsideData -> Result String Msg
fromOutside outsideInfo =
    case outsideInfo.tag of
        -- === Dialogs, Menus, Window State ===
        "CancelCardConfirmed" ->
            Ok CancelCardConfirmed

        -- === DOM ===
        "InitialActivation" ->
            case decodeValue (Dec.oneOf [ Dec.string, Dec.null "" ]) outsideInfo.data of
                Ok cardId ->
                    Ok (InitialActivation cardId)

                Err e ->
                    Err (errorToString e)

        "DragExternalStarted" ->
            Ok DragExternalStarted

        "DropExternal" ->
            case decodeValue Dec.string outsideInfo.data of
                Ok dropText ->
                    Ok (DropExternal dropText)

                Err e ->
                    Err (errorToString e)

        "Paste" ->
            case decodeValue treeOrString outsideInfo.data of
                Ok tree ->
                    Ok (Paste tree)

                Err e ->
                    Err (errorToString e)

        "PasteInto" ->
            case decodeValue treeOrString outsideInfo.data of
                Ok tree ->
                    Ok (PasteInto tree)

                Err e ->
                    Err (errorToString e)

        "FieldChanged" ->
            case decodeValue Dec.string outsideInfo.data of
                Ok str ->
                    Ok (FieldChanged str)

                Err e ->
                    Err (errorToString e)

        "AutoSaveRequested" ->
            Ok AutoSaveRequested

        "FullscreenCardFocused" ->
            case decodeValue (tupleDecoder Dec.string Dec.string) outsideInfo.data of
                Ok ( cardId, fieldId ) ->
                    Ok (FullscreenCardFocused cardId fieldId)

                Err e ->
                    Err (errorToString e)

        "FullscreenChanged" ->
            case decodeValue Dec.bool outsideInfo.data of
                Ok isFullscreen ->
                    Ok (FullscreenChanged isFullscreen)

                Err e ->
                    Err (errorToString e)

        "TextCursor" ->
            case decodeValue textCursorInfoDecoder outsideInfo.data of
                Ok textCursorInfo ->
                    Ok (TextCursor textCursorInfo)

                Err e ->
                    Err (errorToString e)

        "ClickedOutsideCard" ->
            Ok ClickedOutsideCard

        "CheckboxClicked" ->
            case decodeValue (tupleDecoder Dec.string Dec.int) outsideInfo.data of
                Ok ( cardId, checkboxNumber ) ->
                    Ok (CheckboxClicked cardId checkboxNumber)

                Err e ->
                    Err (errorToString e)

        -- === UI ===
        "Keyboard" ->
            case decodeValue Dec.string outsideInfo.data of
                Ok shortcut ->
                    Ok (Keyboard shortcut)

                Err e ->
                    Err (errorToString e)

        "WillPrint" ->
            Ok WillPrint

        -- === Misc ===
        "RecvCollabState" ->
            case decodeValue collabStateDecoder outsideInfo.data of
                Ok collabState ->
                    Ok (RecvCollabState collabState)

                Err e ->
                    Err (errorToString e)

        "RecvCollabUsers" ->
            case decodeValue (Dec.list collabStateDecoder) outsideInfo.data of
                Ok collabStates ->
                    Ok (RecvCollabUsers collabStates)

                Err e ->
                    Err (errorToString e)

        "CollaboratorDisconnected" ->
            case decodeValue Dec.string outsideInfo.data of
                Ok uid ->
                    Ok (CollaboratorDisconnected uid)

                Err e ->
                    Err (errorToString e)

        _ ->
            Err <| "Unexpected info from outside: " ++ outsideInfo.tag


subscribe : (Msg -> msg) -> (String -> msg) -> Sub msg
subscribe tagger onError =
    docMsgs
        (\outsideInfo ->
            case fromOutside outsideInfo of
                Ok msg ->
                    tagger msg

                Err err ->
                    onError err
        )



-- PORT


port docMsgs : (OutsideData -> msg) -> Sub msg
