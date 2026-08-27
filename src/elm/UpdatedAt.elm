module UpdatedAt exposing (UpdatedAt, areEqual, decoder, encode, fromParts, fromString, getHash, getTimestamp, isLTE, maximum, sortNewestFirst, sortOldestFirst, unique, zero)

import Json.Decode as Dec exposing (Decoder)
import Json.Encode as Enc
import List.Extra as ListExtra



-- TYPES & CONSTRUCTORS


type UpdatedAt
    = UpdatedAt { timestamp : Int, counter : Int, hash : String }


type alias Data =
    { timestamp : Int, counter : Int, hash : String }


decoder : Decoder UpdatedAt
decoder =
    Dec.string
        |> Dec.andThen
            (\str ->
                case stringParser str of
                    Just data ->
                        Dec.succeed data

                    Nothing ->
                        Dec.fail "Invalid UpdatedAt string"
            )


fromString : String -> Result String UpdatedAt
fromString str =
    case stringParser str of
        Just data ->
            Ok data

        Nothing ->
            Err "Invalid UpdatedAt string"


fromParts : Int -> Int -> String -> UpdatedAt
fromParts timestamp counter hash =
    UpdatedAt { timestamp = timestamp, counter = counter, hash = hash }


zero : UpdatedAt
zero =
    UpdatedAt { timestamp = 0, counter = 0, hash = "" }



-- EXPOSED FUNCTIONS


sortNewestFirst : (a -> UpdatedAt) -> List a -> List a
sortNewestFirst f l =
    l
        |> List.map (\a -> ( f a, a ))
        |> List.sortWith (\( a, _ ) ( b, _ ) -> compareUpdatedAt a b)
        |> List.map Tuple.second
        |> List.reverse


sortOldestFirst : (a -> UpdatedAt) -> List a -> List a
sortOldestFirst f l =
    sortNewestFirst f l
        |> List.reverse


getTimestamp : UpdatedAt -> Int
getTimestamp (UpdatedAt data) =
    data.timestamp


getHash : UpdatedAt -> String
getHash (UpdatedAt data) =
    data.hash


areEqual : UpdatedAt -> UpdatedAt -> Bool
areEqual (UpdatedAt a) (UpdatedAt b) =
    a.timestamp == b.timestamp && a.counter == b.counter && a.hash == b.hash


unique : List UpdatedAt -> List UpdatedAt
unique l =
    l
        |> ListExtra.uniqueBy toString


maximum : List UpdatedAt -> Maybe UpdatedAt
maximum l =
    l
        |> sortNewestFirst identity
        |> List.head


isLTE : UpdatedAt -> UpdatedAt -> Bool
isLTE ua1 ua2 =
    compareUpdatedAt ua1 ua2
        == LT
        || areEqual ua1 ua2



-- PRIVATE FUNCTIONS


compareUpdatedAt : UpdatedAt -> UpdatedAt -> Order
compareUpdatedAt (UpdatedAt a) (UpdatedAt b) =
    case compare a.timestamp b.timestamp of
        LT ->
            LT

        GT ->
            GT

        EQ ->
            case compare a.counter b.counter of
                LT ->
                    LT

                GT ->
                    GT

                EQ ->
                    compare a.hash b.hash



-- ENCODER / DECODER


encode : UpdatedAt -> Enc.Value
encode ua =
    Enc.string (toString ua)


{-| How the zero stamp is written: not `"0:0:"` but the bare `"0"`. It is the
wire format -- `ZERO_STAMP` in `src/shared/stamps.js`, and the `chk` sent as the
pull checkpoint for a document with nothing synced yet -- so it is spelled once
here and read back by `stringParser` below. It used to be spelled only in
`toString`, which left this module unable to parse its own output (S10).
-}
zeroString : String
zeroString =
    "0"


toString : UpdatedAt -> String
toString (UpdatedAt data) =
    case ( data.timestamp, data.counter, data.hash ) of
        ( 0, 0, "" ) ->
            zeroString

        _ ->
            String.join ":" [ String.fromInt data.timestamp, String.fromInt data.counter, data.hash ]


stringParser : String -> Maybe UpdatedAt
stringParser str =
    if str == zeroString then
        Just zero

    else
        case String.split ":" str of
            [ timestamp, counter, hash ] ->
                case ( String.toInt timestamp, String.toInt counter ) of
                    ( Just ts, Just ctr ) ->
                        UpdatedAt { timestamp = ts, counter = ctr, hash = hash }
                            |> Just

                    _ ->
                        Nothing

            _ ->
                Nothing
