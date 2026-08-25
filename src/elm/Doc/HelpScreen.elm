module Doc.HelpScreen exposing (view, viewShortcuts)

import Ant.Icons.Svg as Icons
import Feature
import Features exposing (Feature(..))
import Html exposing (Html, a, button, div, h2, h3, h4, kbd, li, span, table, td, th, thead, ul)
import Html.Attributes exposing (class, colspan, height, href, id, style, target, width)
import Html.Events exposing (onClick)
import SharedUI exposing (ctrlOrCmdText)
import Translation exposing (TranslationId(..), tr)
import Utils exposing (ternary)



-- Translation Helper Function


text : TranslationId -> Html msg
text tid =
    Html.text <| tr tid


textNoTr : String -> Html msg
textNoTr str =
    Html.text str


emptyText : Html msg
emptyText =
    Html.text ""



-- VIEW


view : Bool -> { closeModal : msg } -> List (Html msg)
view isMac msg =
    [ div [ class "modal-overlay", onClick msg.closeModal ] []
    , div [ class "max-width-grid" ]
        [ div [ class "modal", class "help-modal" ]
            [ div [ class "modal-header" ]
                [ h2 [] [ text Help ]
                , div [ class "close-button", onClick msg.closeModal ] [ Icons.closeCircleOutlined [ width 20, height 20 ] ]
                ]
            , div [ class "modal-guts" ]
                (viewShortcuts isMac)
            ]
        ]
    ]


viewShortcuts : Bool -> List (Html msg)
viewShortcuts isMac =
    let
        ctrlOrCmd =
            ctrlOrCmdText isMac
    in
    [ h2 [ id "shortcut-main-title" ] [ text KeyboardShortcuts ]
    , div [ id "shortcut-modes-wrapper" ]
        [ div []
            [ h3 [ id "view-mode-shortcuts-title" ] [ text ViewModeShortcuts ]
            , shortcutTable CardEditCreateDelete (normalEditShortcuts ctrlOrCmd)
            , shortcutTable NavigationMovingCards (normalNavigationShortcuts ctrlOrCmd)
            , shortcutTable CopyPaste (normalCopyShortcuts ctrlOrCmd)
            , shortcutTable SearchingMerging (normalAdvancedShortcuts ctrlOrCmd)
            , shortcutTable HelpInfoDocs (normalOtherShortcuts ctrlOrCmd)
            ]
        , div [ id "mode-divider" ] []
        , div []
            [ h3 [ id "edit-mode-shortcuts-title" ] [ text EditModeShortcuts ]
            , shortcutTable CardSaveCreate (editSaveShortcuts ctrlOrCmd)
            , shortcutTable Formatting (editFormatShortcuts ctrlOrCmd)
            ]
        ]
    ]


shortcutTable : TranslationId -> List (Html msg) -> Html msg
shortcutTable tableTitle tableRows =
    div [ class "shortcut-table-wrapper" ]
        [ h4 [ class "shortcut-table-title" ] [ text tableTitle ]
        , table [ class "shortcut-table" ] tableRows
        ]


keyNoTr : String -> Html msg
keyNoTr str =
    key (NoTr str)


normalEditShortcuts : String -> List (Html msg)
normalEditShortcuts ctrlOrCmd =
    [ shortcutRow EditCard [ key EnterKey ]
    , shortcutRow EditCardFullscreen [ key ShiftKey, key EnterKey ]
    , shortcutRow AddCardBelow [ keyNoTr ctrlOrCmd, keyNoTr "↓", text Or, keyNoTr ctrlOrCmd, keyNoTr "J" ]
    , shortcutRow AddCardAbove [ keyNoTr ctrlOrCmd, keyNoTr "↑", text Or, keyNoTr ctrlOrCmd, keyNoTr "K" ]
    , shortcutRow AddCardToRight [ keyNoTr ctrlOrCmd, keyNoTr "→", text Or, keyNoTr ctrlOrCmd, keyNoTr "L" ]
    , shortcutRow DeleteCard [ keyNoTr ctrlOrCmd, key Backspace ]
    ]


normalNavigationShortcuts : String -> List (Html msg)
normalNavigationShortcuts ctrlOrCmd =
    [ shortcutRow GoUpDownLeftRight [ keyNoTr "↑", keyNoTr "↓", keyNoTr "←", keyNoTr "→", text Or, keyNoTr "H", keyNoTr "J", keyNoTr "K", keyNoTr "L" ]
    , shortcutRow GoToBeginningOfGroup [ key PageUp ]
    , shortcutRow GoToEndOfGroup [ key PageDown ]
    , shortcutRow GoToBeginningOfColumn [ key HomeKey ]
    , shortcutRow GoToEndOfColumn [ key EndKey ]
    , shortcutRow MoveCurrentCard [ key AltKey, key AnyOfAbove, text Or, dragCommand DragCard ]
    ]


normalAdvancedShortcuts : String -> List (Html msg)
normalAdvancedShortcuts ctrlOrCmd =
    [ shortcutRow Search [ keyNoTr "/" ]
    , shortcutRow ClearSearch [ key EscKey ]
    , shortcutRow MergeCardUp [ keyNoTr ctrlOrCmd, key ShiftKey, keyNoTr "↑", text Or, keyNoTr ctrlOrCmd, key ShiftKey, keyNoTr "J" ]
    , shortcutRow MergeCardDown [ keyNoTr ctrlOrCmd, key ShiftKey, keyNoTr "↓", text Or, keyNoTr ctrlOrCmd, key ShiftKey, keyNoTr "K" ]
    ]


normalCopyShortcuts : String -> List (Html msg)
normalCopyShortcuts ctrlOrCmd =
    [ Html.tr [] [ th [ colspan 2 ] [ text WorksAcrossDocuments ] ]
    , shortcutRow CopyCurrent [ keyNoTr ctrlOrCmd, keyNoTr "C" ]
    , shortcutRow PasteBelow [ keyNoTr ctrlOrCmd, keyNoTr "V" ]
    , shortcutRow PasteAsChild [ keyNoTr ctrlOrCmd, key ShiftKey, keyNoTr "V" ]
    , shortcutRow InsertSelected [ dragCommand DragSelected ]
    ]


normalOtherShortcuts : String -> List (Html msg)
normalOtherShortcuts ctrlOrCmd =
    [ shortcutRow WordCounts [ keyNoTr "W" ]
    , shortcutRow SwitchDocuments [ keyNoTr ctrlOrCmd, keyNoTr "O" ]
    , shortcutRow ThisHelpScreen [ keyNoTr "?" ]
    ]


editSaveShortcuts : String -> List (Html msg)
editSaveShortcuts ctrlOrCmd =
    [ shortcutRow SaveChanges [ keyNoTr ctrlOrCmd, keyNoTr "S" ]
    , shortcutRow SaveChangesAndExit [ keyNoTr ctrlOrCmd, key EnterKey ]
    , shortcutRow AddCardBelowSplit [ keyNoTr ctrlOrCmd, keyNoTr "J" ]
    , shortcutRow AddCardAboveSplit [ keyNoTr ctrlOrCmd, keyNoTr "K" ]
    , shortcutRow AddCardToRightSplit [ keyNoTr ctrlOrCmd, keyNoTr "L" ]
    , shortcutRow ExitEditMode [ key EscKey ]
    ]


editFormatShortcuts : String -> List (Html msg)
editFormatShortcuts ctrlOrCmd =
    [ shortcutRow BoldSelection [ keyNoTr ctrlOrCmd, keyNoTr "B" ]
    , shortcutRow ItalicizeSelection [ keyNoTr ctrlOrCmd, keyNoTr "I" ]
    , shortcutRow InsertLink [ keyNoTr ctrlOrCmd, key AltKey, keyNoTr "K" ]
    , shortcutRow SetTitleLevel [ key AltKey, keyNoTr "1", text (NoTr " ... "), keyNoTr "6" ]
    ]


shortcutRow : TranslationId -> List (Html msg) -> Html msg
shortcutRow desc keys =
    Html.tr [ class "shortcut-row" ] [ td [ style "text-align" "right" ] keys, td [] [ Html.text (": " ++ tr desc) ] ]


key : TranslationId -> Html msg
key str =
    span [ class "shortcut-key" ] [ text str ]


dragCommand : TranslationId -> Html msg
dragCommand str =
    span [ class "shortcut-key", class "drag-command" ] [ text str ]
