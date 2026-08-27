module Doc.Switcher exposing (Model, currentId, down, encodeDocs, search, selectedId, up)

import Doc.List as DocList
import Doc.Metadata as Metadata exposing (Metadata)
import Json.Encode as Enc
import List.Extra as ListExtra



-- MODEL


type alias Model =
    { currentDocument : Metadata
    , selectedDocument : Maybe String
    , searchField : String
    , docList : DocList.Model
    }



-- UPDATE


down : Model -> Model
down ({ currentDocument, selectedDocument, searchField, docList } as model) =
    case selectedDocument of
        Just selected ->
            let
                newSel =
                    case filteredDocs model of
                        Just docs ->
                            docs
                                |> List.map (\md -> ( md, selected == Metadata.getDocId md ))
                                |> ListExtra.takeWhileRight (not << Tuple.second)
                                |> List.head
                                |> Maybe.map Tuple.first
                                |> Maybe.map Metadata.getDocId
                                |> Maybe.withDefault selected

                        Nothing ->
                            selected
            in
            { model | selectedDocument = Just newSel }

        Nothing ->
            { model
                | selectedDocument =
                    filteredDocs model
                        |> Maybe.andThen List.head
                        |> Maybe.map Metadata.getDocId
            }


up : Model -> Model
up ({ currentDocument, selectedDocument, searchField, docList } as model) =
    case selectedDocument of
        Just selected ->
            let
                newSel =
                    case filteredDocs model of
                        Just docs ->
                            docs
                                |> List.map (\md -> ( md, selected == Metadata.getDocId md ))
                                |> ListExtra.takeWhile (not << Tuple.second)
                                |> List.reverse
                                |> List.head
                                |> Maybe.map Tuple.first
                                |> Maybe.map Metadata.getDocId
                                |> Maybe.withDefault selected

                        Nothing ->
                            selected
            in
            { model | selectedDocument = Just newSel }

        Nothing ->
            { model
                | selectedDocument =
                    filteredDocs model
                        |> Maybe.andThen List.head
                        |> Maybe.map Metadata.getDocId
            }


search : String -> Model -> Model
search term model =
    let
        newModel =
            { model | searchField = term }
    in
    { newModel
        | selectedDocument =
            filteredDocs newModel
                |> Maybe.andThen List.head
                |> Maybe.map Metadata.getDocId
    }



-- VIEW


{-| The filtered, sorted list the switcher shows, as JSON for
<gw-switcher-modal>. Filtering and sort order stay here; only the markup
moved to src/ui/switcher-modal.ts.
-}
encodeDocs : Model -> Enc.Value
encodeDocs ({ currentDocument, searchField, docList } as model) =
    filteredDocs model
        |> Maybe.withDefault []
        |> Enc.list
            (\md ->
                Enc.object
                    [ ( "id", Enc.string (Metadata.getDocId md) )
                    , ( "name"
                      , Metadata.getDocName md
                            |> Maybe.map Enc.string
                            |> Maybe.withDefault Enc.null
                      )
                    ]
            )


selectedId : Model -> String
selectedId { selectedDocument, currentDocument } =
    selectedDocument |> Maybe.withDefault (Metadata.getDocId currentDocument)


currentId : Model -> String
currentId { currentDocument } =
    Metadata.getDocId currentDocument


-- HELPERS


filteredDocs : Model -> Maybe (List Metadata)
filteredDocs { docList, currentDocument, searchField } =
    docList
        |> DocList.switchListSort currentDocument
        |> DocList.filter searchField
        |> DocList.toList
