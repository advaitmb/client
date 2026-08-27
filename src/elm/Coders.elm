module Coders exposing (collabStateDecoder, collabStateEncoder, lazyRecurse, maybeToValue, sortByDecoder, sortByEncoder, treeOrString, treeToJSON, treeToMarkdownString, treeToOPML, treeToValue, tupleDecoder, tupleToValue)

import Json.Decode as Json exposing (..)
import Json.Encode as Enc
import Types exposing (..)



-- Tree


treeToValue : Tree -> Enc.Value
treeToValue tree =
    case tree.children of
        Children c ->
            Enc.object
                [ ( "id", Enc.string tree.id )
                , ( "content", Enc.string tree.content )
                , ( "children", Enc.list treeToValue c )
                ]


treeDecoder : Decoder Tree
treeDecoder =
    Json.map3 Tree
        (field "id" string)
        (field "content" string)
        (oneOf
            [ field
                "children"
                (list (lazyRecurse (\_ -> treeDecoder))
                    |> Json.map Children
                )
            , succeed (Children [])
            ]
        )


treeOrString : Decoder Tree
treeOrString =
    Json.oneOf
        [ treeDecoder
        , Json.map (\str -> Tree "0" str (Children [])) Json.string
        ]



-- ViewState


collabStateDecoder : Decoder Collaborator
collabStateDecoder =
    Json.map4 Collaborator
        (field "uid" string)
        (field "u" string)
        (field "m" modeDecoder)
        (succeed 0)



-- Mode


collabStateEncoder : CollabStateMode -> Enc.Value
collabStateEncoder mode =
    case mode of
        CollabActive id ->
            tupleToValue Enc.string ( "a", id )

        CollabEditing id ->
            tupleToValue Enc.string ( "e", id )


modeDecoder : Decoder CollabStateMode
modeDecoder =
    let
        modeHelp : ( String, String ) -> Decoder CollabStateMode
        modeHelp ( tag, idIn ) =
            case ( tag, idIn ) of
                ( "a", id ) ->
                    succeed (CollabActive id)

                ( "e", id ) ->
                    succeed (CollabEditing id)

                _ ->
                    fail <| "Failed mode decoder"
    in
    tupleDecoder string string
        |> andThen modeHelp



-- JSON


treeToJSON : Bool -> Tree -> Enc.Value
treeToJSON withRoot tree =
    if withRoot then
        Enc.list treeToJSONrecurse [ tree ]

    else
        case tree.children of
            Children c ->
                Enc.list treeToJSONrecurse c


treeToJSONrecurse : Tree -> Enc.Value
treeToJSONrecurse tree =
    case tree.children of
        Children c ->
            Enc.object
                [ ( "content", Enc.string tree.content )
                , ( "children", Enc.list treeToJSONrecurse c )
                ]


attrEncode s =
    s
        |> String.replace "&" "&amp;"
        |> String.replace "\"" "&quot;"
        |> String.replace "'" "&apos;"
        |> String.replace "<" "&lt;"



-- OPML


treeToOPML : String -> Tree -> String
treeToOPML docname tree =
    "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<opml version=\"2.0\">\n<head><title>"
        ++ (attrEncode docname |> String.replace ">" "&gt;")
        ++ "</title></head>\n<body>"
        ++ treeToOPMLBody tree
        ++ "</body></opml>"


treeToOPMLBody : Tree -> String
treeToOPMLBody tree =
    case tree.children of
        Children c ->
            "<outline text=\"" ++ attrEncode tree.content ++ "\">" ++ (List.map treeToOPMLBody c |> String.join "\n") ++ "</outline>\n"



-- Markdown


treeToMarkdownString : Bool -> Tree -> String
treeToMarkdownString withRoot tree =
    let
        contentList =
            case tree.children of
                Children c ->
                    List.map treeToMarkdownRecurse c
    in
    if withRoot then
        tree.content
            :: contentList
            |> String.join "\n\n"

    else
        contentList
            |> String.join "\n\n"


treeToMarkdownRecurse : Tree -> String
treeToMarkdownRecurse tree =
    case tree.children of
        Children c ->
            [ tree.content ]
                ++ List.map treeToMarkdownRecurse c
                |> String.join "\n\n"



-- SortBy


sortByDecoder : Decoder SortBy
sortByDecoder =
    let
        get id =
            case id of
                "Alphabetical" ->
                    succeed Alphabetical

                "ModifiedAt" ->
                    succeed ModifiedAt

                "CreatedAt" ->
                    succeed CreatedAt

                _ ->
                    fail ("unknown value for SortBy: " ++ id)
    in
    string |> andThen get


sortByEncoder : SortBy -> Enc.Value
sortByEncoder sortBy =
    case sortBy of
        Alphabetical ->
            Enc.string "Alphabetical"

        ModifiedAt ->
            Enc.string "ModifiedAt"

        CreatedAt ->
            Enc.string "CreatedAt"



-- HELPERS


lazyRecurse : (() -> Decoder a) -> Decoder a
lazyRecurse thunk =
    let
        toResult =
            \js -> decodeValue (thunk ()) js
    in
    andThen
        (\a ->
            case toResult a of
                Ok b ->
                    succeed b

                Err err ->
                    fail (errorToString err)
        )
        value


maybeToValue : (a -> Enc.Value) -> Maybe a -> Enc.Value
maybeToValue encoder mb =
    case mb of
        Nothing ->
            Enc.null

        Just v ->
            encoder v


tupleToValue : (a -> Enc.Value) -> ( a, a ) -> Enc.Value
tupleToValue encoder ( aVal, bVal ) =
    Enc.list encoder [ aVal, bVal ]


tupleDecoder : Decoder a -> Decoder b -> Decoder ( a, b )
tupleDecoder a b =
    index 0 a
        |> andThen
            (\aVal ->
                index 1 b
                    |> andThen (\bVal -> succeed ( aVal, bVal ))
            )
