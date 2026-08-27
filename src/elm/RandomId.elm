module RandomId exposing (generate, stringGenerator)

import Random


generate : (String -> msg) -> Cmd msg
generate msgTag =
    Random.generate msgTag (stringGenerator 7)


stringGenerator : Int -> Random.Generator String
stringGenerator numberOfChars =
    Random.int 0 61
        |> Random.map intToValidChar
        |> Random.list numberOfChars
        |> Random.map String.fromList



-- INTERNAL


intToValidChar : Int -> Char
intToValidChar int =
    if int <= 9 then
        -- 0 to 9
        int + 48 |> Char.fromCode

    else if int < 10 + 26 then
        -- A to Z
        int - 10 + 65 |> Char.fromCode

    else
        -- a to z
        int - 10 - 26 + 97 |> Char.fromCode
