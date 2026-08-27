module CodecTest exposing (metadataRoundTrip, updatedAtRoundTrip)

{-| Tests at the ADR-0001 seam 13: a value this client writes decodes back to
itself.

Both subjects here are encoder/decoder pairs whose halves had drifted apart
(CODE_REVIEW.md S10), and neither drift is visible from one side alone -- which
is why the test is the composition rather than either half:

  - `Doc.Metadata.encode` wrote no `collaborators`, which its own `decoder`
    needed to take the branch that reads them, so re-decoding silently reset a
    document's collaborators to `[]`. It also omitted `_rev` for metadata that
    has no revision -- and the decoder required the field to be *present* -- so
    that metadata did not decode back at all.
  - `UpdatedAt.encode zero` produces the bare string `"0"`, which the module's
    own parser rejected. `"0"` is the wire format, shared with
    `src/shared/stamps.js` (`ZERO_STAMP`) and sent as the pull checkpoint for a
    document with nothing synced yet, so the parser is what had to give.

-}

import Doc.Metadata as Metadata exposing (Metadata)
import Expect
import Json.Decode as Dec
import Json.Encode as Enc
import Test exposing (Test, describe, test)
import Time
import UpdatedAt exposing (UpdatedAt)


-- === Doc.Metadata ===


{-| A `trees` row as it reaches Elm (`treeDocToMetadata` in `doc.js`), with any
field overridden.
-}
storedMetadata : List ( String, Enc.Value ) -> Enc.Value
storedMetadata overrides =
    let
        defaults =
            [ ( "docId", Enc.string "tree-abc" )
            , ( "name", Enc.string "Report" )
            , ( "collaborators", Enc.list Enc.string [ "someone@example.com" ] )
            , ( "createdAt", Enc.int 1700000000000 )
            , ( "updatedAt", Enc.int 1700000009000 )
            , ( "_rev", Enc.null )
            ]

        overridden ( key, _ ) =
            List.any (\( overrideKey, _ ) -> overrideKey == key) overrides
    in
    Enc.object (List.filter (not << overridden) defaults ++ overrides)


{-| Everything a `Metadata` will answer about a document. Compared whole, so a
field the round trip loses fails the test even if nothing asks for it yet.
-}
observable :
    Metadata
    ->
        { docId : String
        , docName : Maybe String
        , collaborators : List String
        , createdAt : Int
        , updatedAt : Int
        }
observable metadata =
    { docId = Metadata.getDocId metadata
    , docName = Metadata.getDocName metadata
    , collaborators = Metadata.getCollaborators metadata
    , createdAt = Metadata.getCreatedAt metadata |> Time.posixToMillis
    , updatedAt = Metadata.getUpdatedAt metadata |> Time.posixToMillis
    }


{-| Decode, write back out, and decode again: what a second reader of what this
client wrote would see.
-}
reDecoded : Enc.Value -> Result String Metadata
reDecoded json =
    json
        |> Dec.decodeValue Metadata.decoder
        |> Result.map Metadata.encode
        |> Result.andThen (Dec.decodeValue Metadata.decoder)
        |> Result.mapError Dec.errorToString


expectSurvivesEncoding : Enc.Value -> Expect.Expectation
expectSurvivesEncoding json =
    case ( Dec.decodeValue Metadata.decoder json, reDecoded json ) of
        ( Ok asStored, Ok asReWritten ) ->
            observable asReWritten |> Expect.equal (observable asStored)

        ( Err err, _ ) ->
            Expect.fail ("the stored metadata did not decode: " ++ Dec.errorToString err)

        ( _, Err err ) ->
            Expect.fail ("what the encoder wrote did not decode: " ++ err)


metadataRoundTrip : Test
metadataRoundTrip =
    describe "Document metadata, written and read back"
        [ test "a document's collaborators survive" <|
            \_ ->
                expectSurvivesEncoding
                    (storedMetadata
                        [ ( "collaborators"
                          , Enc.list Enc.string [ "one@example.com", "two@example.com" ]
                          )
                        ]
                    )
        , test "metadata with no revision survives -- it is what the port layer sends" <|
            \_ ->
                expectSurvivesEncoding (storedMetadata [ ( "_rev", Enc.null ) ])
        , test "metadata with a revision survives" <|
            \_ ->
                expectSurvivesEncoding (storedMetadata [ ( "_rev", Enc.string "2-deadbeef" ) ])
        , test "an unnamed document survives" <|
            \_ ->
                expectSurvivesEncoding (storedMetadata [ ( "name", Enc.null ) ])
        , test "collaborators written by an older build, as no field at all, read as none" <|
            \_ ->
                storedMetadata [ ( "collaborators", Enc.null ) ]
                    |> Dec.decodeValue Metadata.decoder
                    |> Result.map Metadata.getCollaborators
                    |> Expect.equal (Ok [])
        ]



-- === UpdatedAt ===


{-| The stamp string an `UpdatedAt` is written as, on the wire and in Dexie. -}
encodedAs : UpdatedAt -> Result String String
encodedAs stamp =
    UpdatedAt.encode stamp
        |> Dec.decodeValue Dec.string
        |> Result.mapError Dec.errorToString


{-| The stamp read back out of what `encode` wrote, through the module's own
decoder.
-}
reParsed : UpdatedAt -> Result String UpdatedAt
reParsed stamp =
    UpdatedAt.encode stamp
        |> Dec.decodeValue UpdatedAt.decoder
        |> Result.mapError Dec.errorToString


updatedAtRoundTrip : Test
updatedAtRoundTrip =
    describe "Stamps, written and read back"
        [ test "the zero stamp round-trips through its own parser" <|
            \_ ->
                reParsed UpdatedAt.zero
                    |> Expect.equal (Ok UpdatedAt.zero)
        , test "the zero stamp is still written as the bare 0 that stamps.js reads" <|
            \_ ->
                -- `ZERO_STAMP` in src/shared/stamps.js, and the `chk` sent for
                -- a document with nothing synced yet. Pinned as the literal:
                -- a round trip alone would pass with any private spelling.
                encodedAs UpdatedAt.zero
                    |> Expect.equal (Ok "0")
        , test "a minted stamp round-trips" <|
            \_ ->
                reParsed (UpdatedAt.fromParts 1700000000000 3 "abc")
                    |> Expect.equal (Ok (UpdatedAt.fromParts 1700000000000 3 "abc"))
        , test "a stamp with an empty hash round-trips" <|
            \_ ->
                reParsed (UpdatedAt.fromParts 1700000000000 0 "")
                    |> Expect.equal (Ok (UpdatedAt.fromParts 1700000000000 0 ""))
        , test "a string that is not a stamp is still rejected" <|
            \_ ->
                UpdatedAt.fromString "garbage"
                    |> Expect.err
        , test "a stamp whose counter is not a number is still rejected" <|
            \_ ->
                UpdatedAt.fromString "1700000000000:x:abc"
                    |> Expect.err
        ]
