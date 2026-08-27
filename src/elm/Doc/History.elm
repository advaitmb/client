module Doc.History exposing (History, checkoutVersion, getCurrentVersionId, idAtIndex, init, revert, sliderState, update)

import Doc.Data as Data
import Http
import List.Zipper as Zipper exposing (Zipper)
import RemoteData exposing (WebData)
import Time
import Types exposing (Tree)



-- MODEL


type History
    = History Tree (Zipper Version)
    | Empty


type alias Version =
    { id : String
    , timestamp : Time.Posix
    , tree : WebData Tree
    }


init : Tree -> Data.Model -> History
init tree data =
    data
        |> Data.getHistoryList
        |> List.map (\( id, timestamp, tree_ ) -> { id = id, timestamp = timestamp, tree = tree_ |> RemoteData.fromMaybe (Http.BadBody "") })
        |> Zipper.fromList
        |> Maybe.map (History tree)
        |> Maybe.withDefault Empty


update : Data.Model -> History -> History
update data model =
    case model of
        History origTree zipper ->
            let
                originalFocusId =
                    Zipper.current zipper |> .id
            in
            data
                |> Data.getHistoryList
                |> List.map (\( id, timestamp, tree_ ) -> { id = id, timestamp = timestamp, tree = tree_ |> RemoteData.fromMaybe (Http.BadBody "") })
                |> Zipper.fromList
                |> Maybe.map (\zv -> Zipper.findFirst (\v -> v.id == originalFocusId) zv |> Maybe.withDefault zv)
                |> Maybe.map (History origTree)
                |> Maybe.withDefault Empty

        Empty ->
            Empty


checkoutVersion : String -> History -> Maybe ( History, Tree )
checkoutVersion id history =
    case history of
        History origTree zipper ->
            zipper
                |> Zipper.findFirst (\v -> v.id == id)
                |> Maybe.map (\z -> ( History origTree z, Zipper.current z |> .tree ))
                |> Maybe.andThen (\( h, tree ) -> tree |> RemoteData.toMaybe |> Maybe.map (\t -> ( h, t )))

        Empty ->
            Nothing


getCurrentVersionId : History -> Maybe String
getCurrentVersionId history =
    case history of
        History _ zipper ->
            zipper
                |> Zipper.current
                |> .id
                |> Just

        Empty ->
            Nothing


revert : History -> Maybe Tree
revert model =
    case model of
        History tree _ ->
            Just tree

        Empty ->
            Nothing



-- VIEW


{-| The slider position and its maximum, for <gw-header>. The index -> version
mapping stays here; the element only reports a position.
-}
sliderState : History -> { index : Int, max : Int }
sliderState history =
    case history of
        History _ zipper ->
            { index = List.length (Zipper.before zipper)
            , max = List.length (Zipper.toList zipper) - 1
            }

        Empty ->
            { index = 0, max = 0 }


idAtIndex : Int -> History -> Maybe String
idAtIndex idx history =
    case history of
        History _ zipper ->
            Zipper.toList zipper |> List.drop idx |> List.head |> Maybe.map .id

        Empty ->
            Nothing
