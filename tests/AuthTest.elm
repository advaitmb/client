module AuthTest exposing (loginValidation, signupRequest)

{-| Tests at the ADR-0001 seam 7: what the login and signup forms accept, and
what the client then asks the server to create an account with.

Both are pure, and both are where a self-hosted server's rules differ from the
hosted one's: the server decides what a password is (so the client cannot turn
away an account it did not create), and there is no mailing list for a signup
to subscribe anyone to.

-}

import Expect
import Json.Decode as Dec
import Json.Encode as Enc
import Page.Login as Login exposing (Field(..))
import Session
import Test exposing (Test, describe, test)
import Validate


{-| The login form as the user left it, validated the way `SubmittedForm` does.
`Ok ()` means the form submits; anything else is what it shows instead.
-}
loginErrors : { email : String, password : String } -> Result (List ( Field, String )) ()
loginErrors credentials =
    Validate.validate Login.credentialsValidator credentials
        |> Result.map (always ())


loginValidation : Test
loginValidation =
    describe "Login, validating the credentials"
        [ test "a password the server accepts but signup would not still logs in" <|
            \_ ->
                loginErrors { email = "user@example.com", password = "shortp" }
                    |> Expect.equal (Ok ())
        , test "a blank password shows exactly one thing to fix" <|
            \_ ->
                loginErrors { email = "user@example.com", password = "" }
                    |> Expect.equal (Err [ ( Password, "Please enter a password." ) ])
        , test "a blank form asks for the email and the password, once each" <|
            \_ ->
                loginErrors { email = "", password = "" }
                    |> Expect.equal
                        (Err
                            [ ( Email, "Please enter an email address." )
                            , ( Password, "Please enter a password." )
                            ]
                        )
        , test "an address that is not an email is still refused" <|
            \_ ->
                loginErrors { email = "not-an-email", password = "hunter2" }
                    |> Expect.equal
                        (Err [ ( Email, "This does not seem to be a valid email." ) ])
        ]


{-| The field names a request body carries, sorted so the assertion does not
depend on the encoder's order.
-}
bodyFields : Enc.Value -> Result String (List String)
bodyFields body =
    Dec.decodeValue (Dec.keyValuePairs Dec.value) body
        |> Result.map (List.map Tuple.first >> List.sort)
        |> Result.mapError Dec.errorToString


signupRequest : Test
signupRequest =
    describe "Signup, the request body"
        [ test "asks for an account with an email and a password, and nothing else" <|
            \_ ->
                Session.signupBody "user@example.com" "hunter2"
                    |> bodyFields
                    |> Expect.equal (Ok [ "email", "password" ])
        , test "sends the credentials the user typed" <|
            \_ ->
                Session.signupBody "user@example.com" "hunter2"
                    |> Dec.decodeValue
                        (Dec.map2 Tuple.pair
                            (Dec.field "email" Dec.string)
                            (Dec.field "password" Dec.string)
                        )
                    |> Result.mapError Dec.errorToString
                    |> Expect.equal (Ok ( "user@example.com", "hunter2" ))
        ]
