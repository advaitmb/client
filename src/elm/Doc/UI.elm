module Doc.UI exposing (documentWordcount, encodeSaveState, encodeStats, renderToast, viewAppLoadingSpinner, viewBreadcrumbs, viewDocumentLoadingSpinner, viewMobileButtons, viewSaveIndicator, viewSearchField, viewShortcuts, viewTooltip)

import Ant.Icons.Svg as AntIcons
import Browser.Dom exposing (Element)
import Coders exposing (treeToMarkdownString)
import Doc.TreeStructure as TreeStructure exposing (defaultTree)
import Doc.TreeUtils as TreeUtils exposing (..)
import GlobalData exposing (GlobalData)
import Html exposing (Html, a, div, h2, h3, h5, hr, input, li, node, pre, span, textarea)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onMouseEnter, onMouseLeave)
import Html.Extra exposing (viewIf)
import Import.Template exposing (Template(..))
import Json.Encode as Enc
import Markdown.Block
import Markdown.Html
import Markdown.Parser
import Markdown.Renderer exposing (Renderer)
import Octicons as Icon exposing (defaultOptions)
import Regex exposing (Regex, replace)
import Route
import Session exposing (LoggedIn)
import SharedUI exposing (ctrlOrCmdText)
import Svg exposing (g, svg)
import Svg.Attributes exposing (d, fill, fontFamily, fontSize, fontWeight, preserveAspectRatio, stroke, strokeDasharray, strokeDashoffset, strokeLinecap, strokeLinejoin, strokeMiterlimit, strokeWidth, textAnchor, version, viewBox)
import Time exposing (posixToMillis)
import Toast
import Translation exposing (TranslationId(..), tr)
import Types exposing (Children(..), CursorPosition(..), SortBy(..), TextCursorInfo, Toast, ToastRole(..), TooltipPosition(..), ViewMode(..), ViewState)
import Utils exposing (asButton, emptyText, ternary, text, textNoTr)


{-| The save state of the document, as `<gw-save-indicator>`
(`src/ui/save-indicator.ts`) renders it. Used by the fullscreen view; the
document header sends the same JSON as an attribute of `<gw-header>`, which
forwards it to the same element.

There used to be two implementations of what "saved" looks like -- this one and
a copy inside `header.ts` -- and they had already drifted apart (S1): the copy
had no "Database Error..." branch and read the zero timestamp of a document
still loading as an offline save. `encodeSaveState` below is now the only place
this state crosses out of Elm, and the element is the only place it is turned
into words, so the next change to it is made once on each side.

-}
viewSaveIndicator :
    { m | dirty : Bool, lastLocalSave : Maybe Time.Posix, lastRemoteSave : Maybe Time.Posix }
    -> Time.Posix
    -> Html msg
viewSaveIndicator saveState currentTime =
    node "gw-save-indicator"
        [ id "save-indicator"
        , attribute "save" (encodeSaveState saveState currentTime)
        ]
        []


{-| The `save` attribute both surfaces pass: what the document's save state is,
and the clock reading the element measures "5 minutes ago" against. Epoch
milliseconds, `null` for "never".
-}
encodeSaveState :
    { m | dirty : Bool, lastLocalSave : Maybe Time.Posix, lastRemoteSave : Maybe Time.Posix }
    -> Time.Posix
    -> String
encodeSaveState { dirty, lastLocalSave, lastRemoteSave } currentTime =
    let
        millis t_ =
            t_ |> Maybe.map (posixToMillis >> Enc.int) |> Maybe.withDefault Enc.null
    in
    Enc.encode 0 <|
        Enc.object
            [ ( "dirty", Enc.bool dirty )
            , ( "lastLocalSave", millis lastLocalSave )
            , ( "lastRemoteSave", millis lastRemoteSave )
            , ( "now", Enc.int (posixToMillis currentTime) )
            ]


viewBreadcrumbs : (String -> msg) -> List ( String, String ) -> Html msg
viewBreadcrumbs clickedCrumbMsg cardIdsAndTitles =
    let
        defaultMarkdown =
            Markdown.Renderer.defaultHtmlRenderer

        firstElementOnly : a -> List a -> a
        firstElementOnly d l =
            List.head l |> Maybe.withDefault d

        markdownParser tag =
            Markdown.Html.tag tag (\rc -> List.head rc |> Maybe.withDefault emptyText)

        textRenderer : Renderer (Html msg)
        textRenderer =
            { defaultMarkdown
                | text = Html.text
                , codeSpan = Html.text
                , image = always emptyText
                , heading = \{ rawText } -> Html.text (String.trim rawText)
                , paragraph = firstElementOnly emptyText
                , blockQuote = firstElementOnly emptyText
                , orderedList = \i l -> List.map (firstElementOnly emptyText) l |> firstElementOnly emptyText
                , unorderedList =
                    \l ->
                        List.map
                            (\li ->
                                case li of
                                    Markdown.Block.ListItem _ children ->
                                        children |> firstElementOnly emptyText
                            )
                            l
                            |> firstElementOnly emptyText
                , html = Markdown.Html.oneOf ([ "p", "h1", "h2", "h3", "h4", "h5", "h6", "style", "code", "span", "pre" ] |> List.map markdownParser)
            }

        renderedContent : String -> List (Html msg)
        renderedContent content =
            content
                |> Markdown.Parser.parse
                |> Result.mapError deadEndsToString
                |> Result.andThen (\ast -> Markdown.Renderer.render textRenderer ast)
                |> Result.withDefault [ Html.text "<parse error>" ]

        deadEndsToString deadEnds =
            deadEnds
                |> List.map Markdown.Parser.deadEndToString
                |> String.join "\n"

        -- A `div` rather than a `button`, and keyboard-operable by hand: the
        -- crumb's label is the card's title rendered as markdown, which can
        -- contain a link, and a `<button>` may not contain one. `Utils.asButton`
        -- carries the reasoning, including why the keystroke is stopped from
        -- reaching the global shortcuts.
        viewCrumb ( id, content ) =
            div (asButton (clickedCrumbMsg id)) [ span [] (renderedContent content) ]
    in
    div [ id "breadcrumbs", attribute "data-private" "lipsum" ] (List.map viewCrumb cardIdsAndTitles)



-- SIDEBAR


viewAppLoadingSpinner : Bool -> Html msg
viewAppLoadingSpinner sidebarOpen =
    div [ id "app-root", class "loading" ]
        ([ div [ id "document-header" ] []
         , div [ id "loading-overlay" ] []
         , div [ class "spinner" ] [ div [ class "bounce1" ] [], div [ class "bounce2" ] [], div [ class "bounce3" ] [] ]
         ]
            ++ [ -- the same element, told to render but wire nothing up
                 node "gw-sidebar"
                    [ attribute "open" (ternary sidebarOpen "yes" "no")
                    , attribute "static" ""
                    ]
                    []
               ]
        )


viewDocumentLoadingSpinner : List (Html msg)
viewDocumentLoadingSpinner =
    [ div [ id "document-header" ] []
    , div [ id "loading-overlay" ] []
    , div [ class "spinner" ] [ div [ class "bounce1" ] [], div [ class "bounce2" ] [], div [ class "bounce3" ] [] ]
    ]



-- MODALS




encodeStats :
    { activeCardId : String
    , workingTree : TreeStructure.Model
    , startingWordcount : Int
    }
    -> Enc.Value
encodeStats model =
    let
        stats =
            getStats model
    in
    Enc.object
        [ ( "cardWords", Enc.int stats.cardWords )
        , ( "subtreeWords", Enc.int stats.subtreeWords )
        , ( "groupWords", Enc.int stats.groupWords )
        , ( "columnWords", Enc.int stats.columnWords )
        , ( "sessionWords", Enc.int (stats.documentWords - model.startingWordcount) )
        , ( "documentWords", Enc.int stats.documentWords )
        , ( "cardChars", Enc.int stats.cardChars )
        , ( "subtreeChars", Enc.int stats.subtreeChars )
        , ( "groupChars", Enc.int stats.groupChars )
        , ( "columnChars", Enc.int stats.columnChars )
        , ( "documentChars", Enc.int stats.documentChars )
        , ( "cards", Enc.int stats.cards )
        ]


-- DOCUMENT


viewSearchField : (String -> msg) -> { m | viewState : ViewState, globalData : GlobalData } -> Html msg
viewSearchField searchFieldMsg { viewState, globalData } =
    let
        maybeSearchIcon =
            if viewState.searchField == Nothing then
                Icon.search (defaultOptions |> Icon.color "#445" |> Icon.size 12)

            else
                emptyText
    in
    case viewState.viewMode of
        Normal _ ->
            div
                [ id "search-field" ]
                [ input
                    [ type_ "search"
                    , id "search-input"
                    , required True
                    , title (tr PressToSearch)
                    , onInput searchFieldMsg
                    ]
                    []
                , maybeSearchIcon
                ]

        _ ->
            div
                [ id "search-field" ]
                []


viewMobileButtons :
    { edit : msg
    , save : msg
    , cancel : msg
    , plusRight : msg
    , plusDown : msg
    , plusUp : msg
    , navLeft : msg
    , navUp : msg
    , navDown : msg
    , navRight : msg
    }
    -> Bool
    -> Html msg
viewMobileButtons msgs isEditing =
    if isEditing then
        div [ id "mobile-buttons", class "footer" ]
            [ span [ id "mbtn-cancel", class "mobile-button", onClick msgs.cancel ] [ AntIcons.stopOutlined [ width 18 ] ]
            , span [ id "mbtn-save", class "mobile-button", onClick msgs.save ] [ AntIcons.checkOutlined [ width 18 ] ]
            ]

    else
        div [ id "mobile-buttons", class "footer" ]
            [ span [ id "mbtn-edit", class "mobile-button", onClick msgs.edit ] [ AntIcons.editTwoTone [ width 18 ] ]
            , span [ id "mbtn-add-right", class "mobile-button", onClick msgs.plusRight ] [ AntIcons.plusSquareTwoTone [ width 18 ], AntIcons.rightOutlined [ width 14 ] ]
            , span [ id "mbtn-add-down", class "mobile-button", onClick msgs.plusDown ] [ AntIcons.plusSquareTwoTone [ width 18 ], AntIcons.downOutlined [ width 14 ] ]
            , span [ id "mbtn-add-up", class "mobile-button", onClick msgs.plusUp ] [ AntIcons.plusSquareTwoTone [ width 18 ], AntIcons.upOutlined [ width 14 ] ]
            , span [ id "mbtn-nav-left", class "mobile-button", onClick msgs.navLeft ] [ AntIcons.caretLeftOutlined [ width 18 ] ]
            , span [ id "mbtn-nav-up", class "mobile-button", onClick msgs.navUp ] [ AntIcons.caretUpOutlined [ width 18 ] ]
            , span [ id "mbtn-nav-down", class "mobile-button", onClick msgs.navDown ] [ AntIcons.caretDownOutlined [ width 18 ] ]
            , span [ id "mbtn-nav-right", class "mobile-button", onClick msgs.navRight ] [ AntIcons.caretRightOutlined [ width 18 ] ]
            ]


viewShortcuts :
    { toggledShortcutTray : msg, tooltipRequested : String -> TooltipPosition -> TranslationId -> msg, tooltipClosed : msg }
    ->
        { isOpen : Bool
        , isMac : Bool
        , children : Children
        , textCursorInfo : TextCursorInfo
        , viewMode : ViewMode
        }
    -> List (Html msg)
viewShortcuts msgs { isOpen, isMac, children, textCursorInfo, viewMode } =
    let
        isTextSelected =
            textCursorInfo.selected

        isOnly =
            case children of
                Children [ singleRoot ] ->
                    if singleRoot.children == Children [] then
                        True

                    else
                        False

                _ ->
                    False

        viewIfNotOnly content =
            if not isOnly then
                content

            else
                emptyText

        addInsteadOfSplit =
            textCursorInfo.position == End || textCursorInfo.position == Empty

        spanSplit key descAdd descSplit =
            if addInsteadOfSplit then
                shortcutSpan [ NoTr ctrlOrCmd, NoTr key ] descAdd

            else
                shortcutSpan [ NoTr ctrlOrCmd, NoTr key ] descSplit

        splitChild =
            spanSplit "L" AddChildAction SplitChildAction

        splitBelow =
            spanSplit "J" AddBelowAction SplitBelowAction

        splitAbove =
            spanSplit "K" AddAboveAction SplitUpwardAction

        shortcutSpanEnabled enabled keys desc =
            let
                keySpans =
                    keys
                        |> List.map (\k -> span [ class "shortcut-key" ] [ text k ])
            in
            span
                [ classList [ ( "disabled", not enabled ) ] ]
                (keySpans
                    ++ [ textNoTr (" " ++ tr desc) ]
                )

        shortcutSpan =
            shortcutSpanEnabled True

        formattingSpan markup =
            span [] [ pre [ class "formatting-text" ] [ text markup ] ]

        ctrlOrCmd =
            ctrlOrCmdText isMac
    in
    if isOpen then
        let
            iconColor =
                Icon.color "#445"
        in
        case viewMode of
            Normal _ ->
                [ div
                    [ id "shortcuts-tray", classList [ ( "open", isOpen ) ], onClick msgs.toggledShortcutTray ]
                    [ div [ id "shortcuts" ]
                        ([ h3 [] [ text KeyboardShortcuts ]
                         , h5 [] [ text EditCards ]
                         , shortcutSpan [ EnterKey ] EnterAction
                         , shortcutSpan [ ShiftKey, EnterKey ] EditFullscreenAction
                         , viewIfNotOnly <| h5 [] [ text Navigate ]
                         , viewIfNotOnly <| shortcutSpan [ NoTr "↑", NoTr "↓", NoTr "←", NoTr "→" ] ArrowsAction
                         , h5 [] [ text AddNewCards ]
                         , shortcutSpan [ NoTr ctrlOrCmd, NoTr "→" ] AddChildAction
                         , shortcutSpan [ NoTr ctrlOrCmd, NoTr "↓" ] AddBelowAction
                         , shortcutSpan [ NoTr ctrlOrCmd, NoTr "↑" ] AddAboveAction
                         ]
                            ++ [ viewIfNotOnly <| h5 [] [ text MoveAndDelete ]
                               , viewIfNotOnly <| shortcutSpan [ AltKey, ArrowKeys ] MoveAction
                               , viewIfNotOnly <| shortcutSpan [ NoTr ctrlOrCmd, Backspace ] DeleteAction
                               , viewIfNotOnly <| h5 [] [ text MergeCards ]
                               , viewIfNotOnly <| shortcutSpan [ NoTr ctrlOrCmd, ShiftKey, NoTr "↓" ] MergeDownAction
                               , viewIfNotOnly <| shortcutSpan [ NoTr ctrlOrCmd, ShiftKey, NoTr "↑" ] MergeUpAction
                               , hr [] []
                               , h5 [] [ text OtherShortcuts ]
                               , shortcutSpan [ NoTr "w" ] DisplayWordCounts
                               , shortcutSpan [ NoTr ctrlOrCmd, NoTr "O" ] QuickDocumentSwitcher
                               ]
                        )
                    ]
                ]

            _ ->
                [ div
                    [ id "shortcuts-tray", classList [ ( "open", isOpen ) ], onClick msgs.toggledShortcutTray ]
                    [ div [ id "shortcuts" ]
                        [ h3 [] [ text KeyboardShortcuts ]
                        , h3 [] [ text EditMode ]
                        , h5 [] [ text SaveOrCancelChanges ]
                        , shortcutSpan [ NoTr ctrlOrCmd, EnterKey ] ToSaveChanges
                        , shortcutSpan [ EscKey ] ToCancelChanges
                        , if addInsteadOfSplit then
                            h5 [] [ text AddNewCards ]

                          else
                            h5 [] [ text SplitAtCursor ]
                        , splitChild
                        , splitBelow
                        , splitAbove
                        , h5 [] [ text Formatting ]
                        , shortcutSpanEnabled isTextSelected [ NoTr ctrlOrCmd, NoTr "B" ] ForBold
                        , shortcutSpanEnabled isTextSelected [ NoTr ctrlOrCmd, NoTr "I" ] ForItalic
                        , shortcutSpanEnabled isTextSelected [ NoTr ctrlOrCmd, AltKey, NoTr "K" ] ForInsertLink
                        , shortcutSpan [ AltKey, ParenNumber ] SetHeadingLevel
                        , formattingSpan FormattingTitle
                        , formattingSpan FormattingList
                        , formattingSpan FormattingLink
                        , span [ class "markdown-guide" ]
                            [ a [ href "http://commonmark.org/help", target "_blank" ]
                                [ text FormattingGuide
                                , span [ class "icon-container" ] [ Icon.linkExternal (defaultOptions |> iconColor |> Icon.size 14) ]
                                ]
                            ]
                        ]
                    ]
                ]

    else
        [ div
            [ id "shortcuts-tray"
            , onClick msgs.toggledShortcutTray
            , onMouseEnter <| msgs.tooltipRequested "shortcuts-tray" LeftTooltip KeyboardShortcuts
            , onMouseLeave msgs.tooltipClosed
            ]
            [ keyboardIconSvg 24 ]
        ]



-- Word count


type alias Stats =
    { cardWords : Int
    , cardChars : Int
    , subtreeWords : Int
    , subtreeChars : Int
    , groupWords : Int
    , groupChars : Int
    , columnWords : Int
    , columnChars : Int
    , documentWords : Int
    , documentChars : Int
    , cards : Int
    }


toastConfig : (Toast.Msg -> msg) -> Toast.Config msg
toastConfig msg =
    Toast.config msg
        |> Toast.withTrayAttributes [ class "flex flex-column gap-4 fixed top-14 right-4 z-10" ]
        |> Toast.withTransitionAttributes [ class "translate-x-96 opacity-0" ]


viewToast : List (Html.Attribute msg) -> Toast.Info Toast -> Html msg
viewToast toastAttr toast =
    let
        roleClass =
            case toast.content.role of
                Info ->
                    [ class "bg-blue-400" ]

                Warning ->
                    [ class "bg-yellow-400" ]

                Error ->
                    [ class "bg-red-400" ]

                SuccessToast ->
                    [ class "bg-green-400" ]

        deadEndsToString deadEnds =
            deadEnds
                |> List.map Markdown.Parser.deadEndToString
                |> String.join "\n"

        toastRenderedMarkdown =
            toast.content.message
                |> Markdown.Parser.parse
                |> Result.mapError deadEndsToString
                |> Result.andThen (\ast -> Markdown.Renderer.render Markdown.Renderer.defaultHtmlRenderer ast)
                |> Result.withDefault [ Html.text "<parse error>" ]

        sharedClasses =
            [ class "rounded-lg max-w-xs p-6 py-4 drop-shadow-lg transition duration-500" ]
    in
    div
        (toastAttr ++ roleClass ++ sharedClasses)
        toastRenderedMarkdown


renderToast : (Toast.Msg -> msg) -> Toast.Tray Toast -> Html msg
renderToast msg tray =
    -- `viewToast` is handed to `Toast.render` directly. There used to be a
    -- `viewToastFrame` between them whose whole body was `div [] [ viewToast … ]`
    -- (S12): an attribute-less wrapper carrying nothing, which only kept each
    -- toast from being a flex item of the tray it is laid out in.
    Toast.render viewToast tray (toastConfig msg)


viewTooltip : ( Element, TooltipPosition, TranslationId ) -> Html msg
viewTooltip ( el, tipPos, content ) =
    let
        posAttributes =
            case tipPos of
                RightTooltip ->
                    [ style "left" <| ((el.element.x + el.element.width + 5) |> String.fromFloat) ++ "px"
                    , style "top" <| ((el.element.y + el.element.height * 0.5) |> String.fromFloat) ++ "px"
                    , style "transform" "translateY(-50%)"
                    , class "tip-right"
                    ]

                LeftTooltip ->
                    [ style "left" <| ((el.element.x - 5) |> String.fromFloat) ++ "px"
                    , style "top" <| ((el.element.y + el.element.height * 0.5) |> String.fromFloat) ++ "px"
                    , style "transform" "translate(-100%, -50%)"
                    , class "tip-left"
                    ]

                AboveTooltip ->
                    [ style "left" <| ((el.element.x + el.element.width * 0.5) |> String.fromFloat) ++ "px"
                    , style "top" <| ((el.element.y + 5) |> String.fromFloat) ++ "px"
                    , style "transform" "translate(-50%, calc(-100% - 10px))"
                    , class "tip-above"
                    ]

                BelowTooltip ->
                    [ style "left" <| ((el.element.x + el.element.width * 0.5) |> String.fromFloat) ++ "px"
                    , style "top" <| ((el.element.y + el.element.height + 5) |> String.fromFloat) ++ "px"
                    , style "transform" "translateX(-50%)"
                    , class "tip-below"
                    ]

                BelowLeftTooltip ->
                    [ style "left" <| ((el.element.x + el.element.width * 0.5) |> String.fromFloat) ++ "px"
                    , style "top" <| ((el.element.y + el.element.height + 5) |> String.fromFloat) ++ "px"
                    , style "transform" "translateX(calc(-100% + 10px))"
                    , class "tip-below-left"
                    ]
    in
    div ([ class "tooltip" ] ++ posAttributes)
        [ text content, div [ class "tooltip-arrow" ] [] ]


getStats : { m | activeCardId : String, workingTree : TreeStructure.Model } -> Stats
getStats { activeCardId, workingTree } =
    let
        tree =
            workingTree.tree

        cardsTotal =
            (workingTree.tree
                |> TreeUtils.preorderTraversal
                |> List.length
            )
                -- Don't count hidden root
                - 1

        currentTree =
            getTree activeCardId tree
                |> Maybe.withDefault defaultTree

        currentGroup =
            getSiblings activeCardId tree

        ( cardWords, cardChars ) =
            count currentTree.content

        ( subtreeWords, subtreeChars ) =
            count (treeToMarkdownString False currentTree)
                |> Tuple.mapBoth (\w -> w + cardWords) (\c -> c + cardChars)

        ( groupWords, groupChars ) =
            currentGroup
                |> List.map .content
                |> String.join "\n\n"
                |> count

        ( columnWords, columnChars ) =
            getColumn (getDepth 0 tree activeCardId) tree
                -- Maybe (List (List Tree))
                |> Maybe.withDefault [ [] ]
                |> List.concat
                |> List.map .content
                |> String.join "\n\n"
                |> count

        ( treeWords, treeChars ) =
            count (treeToMarkdownString False tree)
    in
    Stats
        cardWords
        cardChars
        subtreeWords
        subtreeChars
        groupWords
        groupChars
        columnWords
        columnChars
        treeWords
        treeChars
        cardsTotal


{-| The whole document's word count: the number the modal shows as "Total",
and the number a writing session starts from (`Page.Doc`'s
`startingWordcount`), so that "Session" can be the difference between them.
-}
documentWordcount : TreeStructure.Model -> Int
documentWordcount { tree } =
    countWords (treeToMarkdownString False tree)


countWords : String -> Int
countWords str =
    let
        punctuation =
            Regex.fromString "[!@#$%^&*():;\"',.]+"
                |> Maybe.withDefault Regex.never
    in
    str
        |> String.toLower
        |> replace punctuation (\_ -> "")
        |> String.words
        |> List.filter ((/=) "")
        |> List.length


count : String -> ( Int, Int )
count str =
    let
        punctuation =
            Regex.fromString "[!@#$%^&*():;\"',.]+"
                |> Maybe.withDefault Regex.never

        wordCounts =
            str
                |> String.toLower
                |> replace punctuation (\_ -> "")
                |> String.words
                |> List.filter ((/=) "")
                |> List.length

        charCounts =
            str
                |> String.toList
                |> List.length
    in
    ( wordCounts, charCounts )


keyboardIconSvg w =
    svg [ version "1.1", viewBox "0 0 172 172", width w ] [ g [ fill "none", Svg.Attributes.fillRule "nonzero", stroke "none", strokeWidth "1", strokeLinecap "butt", strokeLinejoin "miter", strokeMiterlimit "10", strokeDasharray "", strokeDashoffset "0", fontFamily "none", fontWeight "none", fontSize "none", textAnchor "none", Svg.Attributes.style "mix-blend-mode: normal" ] [ Svg.path [ d "M0,172v-172h172v172z", fill "none" ] [], g [ id "original-icon", fill "#000000" ] [ Svg.path [ d "M16.125,32.25c-8.86035,0 -16.125,7.26465 -16.125,16.125v64.5c0,8.86035 7.26465,16.125 16.125,16.125h129c8.86035,0 16.125,-7.26465 16.125,-16.125v-64.5c0,-8.86035 -7.26465,-16.125 -16.125,-16.125zM16.125,43h129c3.02344,0 5.375,2.35156 5.375,5.375v64.5c0,3.02344 -2.35156,5.375 -5.375,5.375h-129c-3.02344,0 -5.375,-2.35156 -5.375,-5.375v-64.5c0,-3.02344 2.35156,-5.375 5.375,-5.375zM21.5,53.75v10.75h10.75v-10.75zM43,53.75v10.75h10.75v-10.75zM64.5,53.75v10.75h10.75v-10.75zM86,53.75v10.75h10.75v-10.75zM107.5,53.75v10.75h10.75v-10.75zM129,53.75v10.75h10.75v-10.75zM21.5,75.25v10.75h10.75v-10.75zM43,75.25v10.75h10.75v-10.75zM64.5,75.25v10.75h10.75v-10.75zM86,75.25v10.75h10.75v-10.75zM107.5,75.25v10.75h10.75v-10.75zM129,75.25v10.75h10.75v-10.75zM53.75,96.75v10.75h53.75v-10.75zM21.5,96.83399v10.79199h21.5v-10.79199zM118.41797,96.83399v10.79199h21.5v-10.79199z" ] [] ] ] ]
