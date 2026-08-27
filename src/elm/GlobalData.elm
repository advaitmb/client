module GlobalData exposing (GlobalData, currentTime, decode, isMac, public, seed, setSeed, updateTime)

import Json.Decode as Dec exposing (Decoder)
import Json.Decode.Pipeline exposing (required)
import Random
import Time


type GlobalData
    = GlobalData
        { seed : Random.Seed
        , currentTime : Time.Posix
        , isMac : Bool
        }


decode : Dec.Value -> GlobalData
decode json =
    case Dec.decodeValue decoder json of
        Ok gData ->
            gData

        Err err ->
            let
                errToSeed =
                    err
                        |> Dec.errorToString
                        |> String.right 10
                        |> String.toList
                        |> List.map Char.toCode
                        |> List.foldl (+) 12345
                        |> Random.initialSeed
            in
            GlobalData
                { seed = errToSeed
                , currentTime = Time.millisToPosix 0
                , isMac = False
                }


decoder : Decoder GlobalData
decoder =
    Dec.succeed
        (\s t os ->
            GlobalData
                { seed = s
                , currentTime = t
                , isMac = os
                }
        )
        |> required "seed" (Dec.int |> Dec.map Random.initialSeed)
        |> required "currentTime" (Dec.int |> Dec.map Time.millisToPosix)
        |> required "isMac" Dec.bool


public : GlobalData
public =
    GlobalData
        { seed = Random.initialSeed 12345
        , currentTime = Time.millisToPosix 0
        , isMac = False
        }



-- GETTERS


seed : GlobalData -> Random.Seed
seed (GlobalData record) =
    record.seed


currentTime : GlobalData -> Time.Posix
currentTime (GlobalData record) =
    record.currentTime


isMac : GlobalData -> Bool
isMac (GlobalData record) =
    record.isMac



-- UPDATE


setSeed : Random.Seed -> GlobalData -> GlobalData
setSeed newSeed (GlobalData record) =
    GlobalData { record | seed = newSeed }


updateTime : Time.Posix -> GlobalData -> GlobalData
updateTime newTime (GlobalData record) =
    GlobalData { record | currentTime = newTime }

