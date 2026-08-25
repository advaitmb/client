module UI.Sidebar exposing (SidebarMenuState(..), SidebarState(..), viewSidebar, viewSidebarStatic)

import Ant.Icons.Svg as AntIcons
import Browser.Dom exposing (Element)
import Css exposing (..)
import Doc.List as DocList exposing (Model(..))
import Feature
import Features exposing (Feature(..))
import GlobalData exposing (GlobalData)
import Html exposing (Html)
import Html.Styled exposing (a, button, div, form, fromUnstyled, h2, hr, img, input, text, toUnstyled)
import Html.Styled.Attributes as A exposing (action, class, classList, css, href, id, method, name, src, style, type_, value)
import Html.Styled.Events exposing (onClick, onMouseEnter, onMouseLeave)
import MD5
import Octicons
import Session exposing (LoggedIn, PaymentStatus(..))
import Translation exposing (Language(..), TranslationId(..), langToString, languageName)
import Types exposing (SortBy, TooltipPosition(..))
import Utils exposing (emptyText, onClickStopStyled, ternary, textElmCss)


type SidebarState
    = SidebarClosed
    | File


type SidebarMenuState
    = NoSidebarMenu
    | Account (Maybe Element)


type alias SidebarMsgs msg =
    { sidebarStateChanged : SidebarState -> msg
    , noOp : msg
    , clickedNew : msg
    , tooltipRequested : String -> TooltipPosition -> TranslationId -> msg
    , tooltipClosed : msg
    , clickedSwitcher : msg
    , clickedHelp : msg
    , logout : msg
    , fileSearchChanged : String -> msg
    , changeSortBy : SortBy -> msg
    , contextMenuOpened : String -> ( Float, Float ) -> msg
    }


viewSidebar :
    GlobalData
    -> LoggedIn
    -> SidebarMsgs msg
    -> String
    -> SortBy
    -> String
    -> DocList.Model
    -> String
    -> Maybe String
    -> SidebarMenuState
    -> SidebarState
    -> Html msg
viewSidebar globalData session msgs currentDocId sortCriteria fileFilter docList accountEmail contextTarget_ dropdownState sidebarState =
    let
        lang =
            GlobalData.language globalData

        isOpen =
            not (sidebarState == SidebarClosed)

        accountOpen =
            case dropdownState of
                Account _ ->
                    True

                _ ->
                    False

        toggle menu =
            if sidebarState == menu then
                msgs.sidebarStateChanged <| SidebarClosed

            else
                msgs.sidebarStateChanged <| menu

        viewIf cond v =
            if cond then
                v

            else
                emptyText

        sidebarButtonCss =
            Css.batch
                [ width (px 40)
                , padding (px 10)
                , cursor pointer
                , property "fill" "var(--ui-1-fg)"
                , hover [ property "fill" "var(--ui-2-fg)" ]
                ]

        sidebarButtonOpen =
            Css.batch
                [ property "background" "var(--background-sidebar-menu)"
                , property "fill" "var(--ui-2-fg)"
                , borderRadius4 (px 5) (px 0) (px 0) (px 5)
                , paddingLeft (px 7)
                , marginLeft (px 3)
                , width (px 37)
                , property "box-shadow" "var(--small-shadow)"
                ]
    in
    div [ id "sidebar", onClick <| toggle File, classList [ ( "open", isOpen ) ] ]
        ([ div
            [ id "brand"
            , css
                []
            ]
            ([ img [ src "../gingko-leaf-logo.svg", A.width 28 ] [] ]
                ++ (if isOpen then
                        [ h2 [ id "brand-name" ] [ text "Gingko Writer" ]
                        , div [ id "sidebar-collapse-icon" ] [ AntIcons.leftOutlined [] |> fromUnstyled ]
                        ]

                    else
                        [ text "" ]
                   )
                ++ [ div [ id "hamburger-icon" ] [ AntIcons.menuOutlined [] |> fromUnstyled ] ]
            )
         , div
            [ id "new-icon"
            , css [ sidebarButtonCss, property "grid-area" "row1-icon" ]
            , onClickStopStyled msgs.clickedNew
            , onMouseEnter <| msgs.tooltipRequested "new-icon" RightTooltip NewDocument
            , onMouseLeave msgs.tooltipClosed
            ]
            [ AntIcons.fileAddOutlined [] |> fromUnstyled ]
         , div
            ([ id "documents-icon"
             , css
                ([ sidebarButtonCss, property "grid-area" "row2-icon" ]
                    ++ ternary isOpen
                        [ sidebarButtonOpen
                        , property "background" "var(--background-sidebar-menu)"
                        , marginLeft (px 4)
                        ]
                        []
                )
             ]
                ++ ternary (not isOpen)
                    [ onMouseEnter <| msgs.tooltipRequested "documents-icon" RightTooltip ShowDocumentList
                    , onMouseLeave msgs.tooltipClosed
                    ]
                    []
            )
            [ if isOpen then
                AntIcons.folderOpenOutlined [] |> fromUnstyled

              else
                AntIcons.folderOutlined [] |> fromUnstyled
            ]
         , viewIf isOpen
            (DocList.viewSidebarList
                { noOp = msgs.noOp
                , filter = msgs.fileSearchChanged
                , changeSortBy = msgs.changeSortBy
                , contextMenu = msgs.contextMenuOpened
                , tooltipRequested = msgs.tooltipRequested
                , tooltipClosed = msgs.tooltipClosed
                }
                currentDocId
                sortCriteria
                contextTarget_
                fileFilter
                docList
            )
            |> fromUnstyled
         , div
            ([ id "document-switcher-icon"
             , onClickStopStyled msgs.clickedSwitcher
             , onMouseEnter <| msgs.tooltipRequested "document-switcher-icon" RightTooltip OpenQuickSwitcher
             , onMouseLeave msgs.tooltipClosed
             , css [ sidebarButtonCss, property "grid-area" "row3-icon" ]
             ]
                ++ ternary (docList == DocList.Success []) [ class "disabled" ] []
            )
            [ AntIcons.fileSearchOutlined [] |> fromUnstyled ]

         ]
        )
        |> toUnstyled


viewSidebarStatic : Bool -> List (Html msg)
viewSidebarStatic sidebarOpen =
    [ div [ id "sidebar", classList [ ( "open", sidebarOpen ) ], class "static" ]
        [ div [ id "brand" ]
            ([ img [ src "../gingko-leaf-logo.svg", A.width 28 ] [] ]
                ++ (if sidebarOpen then
                        [ h2 [ id "brand-name" ] [ textElmCss En (NoTr "Gingko Writer") ]
                        , div [ id "sidebar-collapse-icon" ] [ AntIcons.leftOutlined [] |> fromUnstyled ]
                        ]

                    else
                        [ text "" ]
                   )
            )
        , ternary sidebarOpen (div [ id "sidebar-document-list-wrap" ] []) (text "")
        , div [ id "new-icon", class "sidebar-button" ] [ AntIcons.fileAddOutlined [] |> fromUnstyled ]
        , div [ id "documents-icon", class "sidebar-button", classList [ ( "open", sidebarOpen ) ] ]
            [ if sidebarOpen then
                AntIcons.folderOpenOutlined [] |> fromUnstyled

              else
                AntIcons.folderOutlined [] |> fromUnstyled
            ]
        , div [ id "document-switcher-icon", class "sidebar-button", class "disabled" ] [ AntIcons.fileSearchOutlined [] |> fromUnstyled ]
        , div
            [ id "help-icon", class "sidebar-button" ]
            [ AntIcons.questionCircleFilled [] |> fromUnstyled ]
        , div [ id "notifications-icon", class "sidebar-button" ] [ AntIcons.bellOutlined [] |> fromUnstyled ]
        , div [ id "account-icon", class "sidebar-button" ] [ AntIcons.userOutlined [] |> fromUnstyled ]
        ]
    ]
        |> List.map toUnstyled
