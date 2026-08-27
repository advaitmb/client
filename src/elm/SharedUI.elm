module SharedUI exposing (ctrlOrCmdText, modalWrapper, unsavedChangesAlert)

import Ant.Icons.Svg as Icons
import Html exposing (Html, a, button, div, h1, h2, text)
import Html.Attributes exposing (class, classList, height, id, width)
import Html.Events exposing (onClick)


modalWrapper : msg -> Maybe String -> Maybe (List ( String, Bool )) -> String -> List (Html msg) -> List (Html msg)
modalWrapper closeMsg id_ classList_ titleString body =
    let
        idAttr =
            case id_ of
                Just bodyId ->
                    [ id bodyId ]

                Nothing ->
                    []

        otherClasses =
            case classList_ of
                Just list ->
                    list

                Nothing ->
                    []
    in
    [ div [ class "modal-overlay", onClick closeMsg ] []
    , div [ classList ([ ( "modal", True ) ] ++ otherClasses) ]
        [ div [ class "modal-header" ]
            [ h2 [] [ text titleString ]
            , div [ class "close-button", onClick closeMsg ] [ Icons.closeCircleOutlined [ width 20, height 20 ] ]
            ]
        , div ([ class "modal-guts" ] ++ idAttr) body
        ]
    ]


ctrlOrCmdText : Bool -> String
ctrlOrCmdText isMac =
    if isMac then
        "⌘"

    else
        "Ctrl"


{-| Shown when something would throw away an edit that only exists in the
model: navigating away (Main.handleUrlChange) and logging out
(Page.App.LogoutRequested) both refuse while the document is dirty.
-}
unsavedChangesAlert : Bool -> String
unsavedChangesAlert isMac =
    "You have unsaved changes!\n" ++ ctrlOrCmdText isMac ++ "+enter to save."
