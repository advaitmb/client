module Page.Doc.Export exposing (ExportFormat(..), ExportSelection(..), command, exportView, exportViewError, toMimeType, toString)

import Ant.Icons.Svg as AntIcons
import Api
import Bytes exposing (Bytes)
import Coders exposing (treeToJSON, treeToMarkdownString, treeToOPML)
import Doc.TreeUtils exposing (getColumnById, getLeaves)
import File.Download as Download
import Html exposing (Html, div, node, pre, text)
import Html.Attributes exposing (attribute, class, id)
import Html.Events exposing (onClick, onMouseEnter, onMouseLeave)
import Http
import Json.Encode as Enc
import Translation exposing (TranslationId(..))
import Types exposing (Children(..), TooltipPosition(..), Tree)


type ExportSelection
    = ExportEverything
    | ExportSubtree
    | ExportLeaves
    | ExportCurrentColumn


type ExportFormat
    = PlainText
    | DOCX
    | OPML
    | JSON


command : (String -> Result Http.Error Bytes -> msg) -> String -> String -> ( ExportSelection, ExportFormat ) -> Tree -> Tree -> Cmd msg
command exportedMsg docId docName (( _, exportFormat ) as exportSettings) activeTree fullTree =
    let
        exportedString =
            toString docName exportSettings activeTree fullTree
    in
    case exportFormat of
        JSON ->
            Download.string (docName ++ ".json") (toMimeType JSON) exportedString

        OPML ->
            Download.string (docName ++ ".opml") (toMimeType OPML) exportedString

        PlainText ->
            Download.string (docName ++ ".txt") (toMimeType PlainText) exportedString

        DOCX ->
            Api.exportDocx
                (exportedMsg docName)
                { docId = docId, markdown = exportedString }


toString : String -> ( ExportSelection, ExportFormat ) -> Tree -> Tree -> String
toString docName ( exportSelection, exportFormat ) activeTree fullTree =
    let
        stringFn withRoot tree =
            case exportFormat of
                JSON ->
                    treeToJSON withRoot tree
                        |> Enc.encode 2

                OPML ->
                    treeToOPML docName tree

                _ ->
                    treeToMarkdownString withRoot tree

        currentColumnCards =
            getColumnById activeTree.id fullTree
                |> Maybe.withDefault []
                |> List.concat
                |> List.map (\c -> { c | children = Children [] })

        -- The invisible root every export is written from, holding a selection
        -- of cards as its children. Its own content is empty, which is exactly
        -- the root `ExportEverything` writes.
        flatTree cards =
            Tree "0" "" (Children cards)
    in
    case exportSelection of
        ExportEverything ->
            stringFn False fullTree

        ExportSubtree ->
            stringFn True activeTree

        -- A flat selection of cards is a tree of depth one, so it goes through
        -- the same `stringFn` as the other two: for JSON and Markdown that is
        -- what the hand-rolled branches here already produced (a childless
        -- card renders as its own content), and OPML now gets a real OPML
        -- document instead of Markdown in an `.opml` file (E13).
        ExportLeaves ->
            stringFn False (flatTree (getLeaves fullTree []))

        ExportCurrentColumn ->
            stringFn False (flatTree currentColumnCards)


{-| The one MIME type a downloaded export is saved as. In one place because
OPML was once handed to the browser as the list
"application/xml, text/xml, text/x-opml" -- which is a set of candidates a
client might accept, not a type a file can have (E13).
-}
toMimeType : ExportFormat -> String
toMimeType expFormat =
    case expFormat of
        DOCX ->
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

        JSON ->
            "application/json"

        OPML ->
            "text/x-opml"

        PlainText ->
            "text/plain"


toExtension : ExportFormat -> String
toExtension expFormat =
    case expFormat of
        DOCX ->
            "docx"

        JSON ->
            "json"

        OPML ->
            "opml"

        PlainText ->
            "md"



-- VIEW


exportView :
    { export : msg
    , printRequested : msg
    , tooltipRequested : String -> TooltipPosition -> TranslationId -> msg
    , tooltipClosed : msg
    }
    -> String
    -> ( ExportSelection, ExportFormat )
    -> Tree
    -> Tree
    -> Html msg
exportView msgs docName (( _, exportFormat ) as exportSettings) activeTree fullTree =
    let
        exportFormatString =
            case exportSettings |> Tuple.second of
                DOCX ->
                    DownloadWordFile

                PlainText ->
                    DownloadTextFile

                JSON ->
                    DownloadJSONFile

                OPML ->
                    DownloadOPMLFile

        actionButtons =
            div [ id "export-action-buttons" ]
                [ div
                    [ id "export-download"
                    , onClick msgs.export
                    , onMouseEnter <| msgs.tooltipRequested "export-download" BelowTooltip exportFormatString
                    , onMouseLeave msgs.tooltipClosed
                    ]
                    [ AntIcons.downloadOutlined [] ]
                , div
                    [ id "export-print"
                    , onClick msgs.printRequested
                    , onMouseEnter <| msgs.tooltipRequested "export-print" BelowLeftTooltip PrintThis
                    , onMouseLeave msgs.tooltipClosed
                    ]
                    [ AntIcons.printerOutlined [] ]
                ]
    in
    case exportFormat of
        DOCX ->
            div [ id "export-preview" ]
                [ node "gw-markdown"
                    [ attribute "src" (toString docName exportSettings activeTree fullTree) ]
                    []
                , actionButtons
                ]

        _ ->
            div [ id "export-preview" ]
                [ div [ class "plain", attribute "data-private" "lipsum" ] [ text (toString docName exportSettings activeTree fullTree) ]
                , actionButtons
                ]


exportViewError : String -> Html never
exportViewError error =
    div [ id "export-preview" ] [ text error ]
