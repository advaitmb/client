port module Doc.List exposing (Model(..), encodeSidebarDocs, filter, fromList, getLastUpdated, init, subscribe, switchListSort, toList, update)

import Doc.Metadata as Metadata exposing (Metadata)
import Json.Decode as Dec
import Json.Encode as Enc
import Time
import Types exposing (SortBy(..))



-- MODEL


type Model
    = Loading
    | Success (List Metadata)
    | Failure Dec.Error


init : Model
init =
    Loading


getLastUpdated : Model -> Maybe String
getLastUpdated model =
    case model of
        Success list ->
            list
                |> List.sortBy (Metadata.getUpdatedAt >> Time.posixToMillis)
                |> List.map Metadata.getDocId
                |> List.reverse
                |> List.head

        _ ->
            Nothing


filter : String -> Model -> Model
filter term model =
    case model of
        Success docList ->
            docList
                |> List.filter
                    (\m ->
                        m
                            |> Metadata.getDocName
                            |> Maybe.withDefault "Untitled"
                            |> String.toLower
                            |> String.contains (term |> String.toLower)
                    )
                |> Success

        _ ->
            model


sortBy : SortBy -> List Metadata -> List Metadata
sortBy criteria docList =
    case criteria of
        Alphabetical ->
            docList
                |> List.sortBy (Metadata.getDocName >> Maybe.withDefault "Untitled" >> String.toLower)

        ModifiedAt ->
            docList
                |> List.sortBy (Metadata.getUpdatedAt >> Time.posixToMillis)
                |> List.reverse

        CreatedAt ->
            docList
                |> List.sortBy (Metadata.getCreatedAt >> Time.posixToMillis)
                |> List.reverse


switchListSort : Metadata -> Model -> Model
switchListSort currentDoc model =
    case model of
        Success docList ->
            docList
                |> List.sortBy (Metadata.getUpdatedAt >> Time.posixToMillis)
                |> List.reverse
                |> List.filter (\d -> not (Metadata.isSameDocId d currentDoc))
                |> List.append [ currentDoc ]
                |> Success

        _ ->
            model


toList : Model -> Maybe (List Metadata)
toList model =
    case model of
        Success docs ->
            Just docs

        _ ->
            Nothing


fromList : List Metadata -> Model
fromList docs =
    Success docs



-- UPDATE


update : SortBy -> Model -> Model -> Model
update sortCriteria newModel oldModel =
    case newModel of
        Success docList ->
            sortBy sortCriteria docList |> Success

        _ ->
            newModel



-- VIEW


{-| The sidebar's rows, filtered and sorted, as JSON for <gw-sidebar>.
Filtering and sort order stay here; only the markup moved to src/ui/sidebar.ts.
-}
encodeSidebarDocs : SortBy -> String -> Model -> Enc.Value
encodeSidebarDocs sortCriteria filterField model =
    filter filterField model
        |> toList
        |> Maybe.withDefault []
        |> sortBy sortCriteria
        |> Enc.list
            (\d ->
                Enc.object
                    [ ( "id", Enc.string (Metadata.getDocId d) )
                    , ( "name"
                      , Metadata.getDocName d
                            |> Maybe.map Enc.string
                            |> Maybe.withDefault Enc.null
                      )
                    ]
            )


-- DECODERS


decoderLocal : Dec.Value -> Model
decoderLocal json =
    case Dec.decodeValue Metadata.listDecoder json of
        Ok list ->
            Success list

        Err err ->
            Failure err



-- SUBSCRIPTIONS


port documentListChanged : (Dec.Value -> msg) -> Sub msg


subscribe : (Model -> msg) -> Sub msg
subscribe msg =
    documentListChanged (decoderLocal >> msg)
