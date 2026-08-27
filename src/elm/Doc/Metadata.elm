module Doc.Metadata exposing (Metadata, decoder, encode, getCollaborators, getCreatedAt, getDocId, getDocName, getUpdatedAt, isSameDocId, listDecoder, new, responseDecoder)

import Coders exposing (maybeToValue)
import Json.Decode as Dec exposing (Decoder)
import Json.Decode.Pipeline exposing (optional, required)
import Json.Encode as Enc
import Time


type Metadata
    = Metadata String MetadataRecord


type alias MetadataRecord =
    { docName : Maybe String
    , collaborators : List String
    , createdAt : Time.Posix
    , updatedAt : Time.Posix
    , rev : Maybe String
    }


new : String -> Metadata
new docId =
    Metadata docId
        { docName = Nothing
        , collaborators = []
        , rev = Nothing
        , createdAt = Time.millisToPosix 0
        , updatedAt = Time.millisToPosix 0
        }


getDocId : Metadata -> String
getDocId (Metadata docId _) =
    docId


getDocName : Metadata -> Maybe String
getDocName (Metadata _ { docName }) =
    docName


getCollaborators : Metadata -> List String
getCollaborators (Metadata _ { collaborators }) =
    collaborators


getCreatedAt : Metadata -> Time.Posix
getCreatedAt (Metadata _ { createdAt }) =
    createdAt


getUpdatedAt : Metadata -> Time.Posix
getUpdatedAt (Metadata _ { updatedAt }) =
    updatedAt


isSameDocId : Metadata -> Metadata -> Bool
isSameDocId m1 m2 =
    getDocId m1 == getDocId m2



-- JSON


{-| One document's metadata, from a `trees` row or from what `encode` wrote.

`collaborators` and `_rev` are optional rather than a second whole decoder to
fall back to. That fallback was how S10 hid: it required both fields, so an
object missing either one silently took the branch that reads no collaborators
at all, and a *new* field would have degraded the same way. Optional fields
degrade one field at a time, and say which.

-}
decoder : Decoder Metadata
decoder =
    Dec.succeed (\id n cls c u r -> Metadata id (MetadataRecord n cls c u r))
        |> required "docId" Dec.string
        |> required "name" (Dec.maybe Dec.string)
        |> optional "collaborators" (Dec.list Dec.string) []
        |> required "createdAt" (Dec.int |> Dec.map Time.millisToPosix)
        |> required "updatedAt" (Dec.int |> Dec.map Time.millisToPosix)
        |> optional "_rev" (Dec.maybe Dec.string) Nothing


listDecoder : Decoder (List Metadata)
listDecoder =
    Dec.list decoder


responseDecoder : Decoder (List Metadata)
responseDecoder =
    Dec.map5 (\id n cls c u -> Metadata id (MetadataRecord n cls c u Nothing))
        (Dec.field "id" Dec.string)
        (Dec.field "name" (Dec.maybe Dec.string))
        (Dec.field "collaborators" (Dec.list Dec.string))
        (Dec.field "createdAt" Dec.int |> Dec.map Time.millisToPosix)
        (Dec.field "updatedAt" Dec.int |> Dec.map Time.millisToPosix)
        |> Dec.list


{-| Everything `decoder` reads, so that what this writes decodes back to the
same metadata (S10). `collaborators` was missing, which cost a document its
collaborators on every re-decode; `_rev` is the one field that may be absent,
because `_id`/`_rev` are CouchDB's and a null revision there would be a lie.
-}
encode : Metadata -> Enc.Value
encode (Metadata docId { docName, collaborators, createdAt, updatedAt, rev }) =
    Enc.object
        ([ ( "_id", Enc.string "metadata" )
         , ( "docId", Enc.string docId )
         , ( "name", maybeToValue Enc.string docName )
         , ( "collaborators", Enc.list Enc.string collaborators )
         , ( "createdAt", Enc.int (Time.posixToMillis createdAt) )
         , ( "updatedAt", Enc.int (Time.posixToMillis updatedAt) )
         ]
            ++ (case rev of
                    Just revData ->
                        [ ( "_rev", Enc.string revData ) ]

                    Nothing ->
                        []
               )
        )
