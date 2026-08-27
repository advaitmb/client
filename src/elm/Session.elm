port module Session exposing (Guest, LoggedIn, Session(..), UserSource(..), confirmEmail, copyNaming, decode, documents, endFirstRun, features, fileMenuOpen, fromLegacy, getDocName, getMetadata, isFirstRun, isNotConfirmed, isOwner, lastDocId, lastDocIdSetting, logout, name, public, requestForgotPassword, requestLogin, requestResetPassword, requestSignup, responseDecoder, setFileOpen, setShortcutTrayOpen, setSortBy, shortcutTrayOpen, sortBy, storeLastDocId, storeLogin, storeSignup, sync, toGuest, updateDocuments, userLoggedIn, userLoggedOut, userSettingsChange)

import Coders exposing (sortByDecoder)
import Doc.List as DocList exposing (Model(..))
import Doc.Metadata as Metadata exposing (Metadata)
import Features exposing (Feature)
import Http
import Json.Decode as Dec exposing (Decoder)
import Json.Decode.Pipeline exposing (optional, required)
import Json.Encode as Enc
import List.Extra as ListExtra
import Outgoing exposing (Msg(..), send)
import Regex
import Time
import Types exposing (SortBy(..))



-- MODEL


type Session
    = GuestSession Guest
    | LoggedInSession LoggedIn


{-| A guest carries the preferences of the user who was last logged in here,
so that logging back in cannot reset them (E3): the login response is decoded
against them, and only what the server actually says overrides them.
-}
type Guest
    = Guest SessionData UserPrefs


type LoggedIn
    = LoggedIn SessionData UserData


type alias SessionData =
    { fileMenuOpen : Bool
    , lastDocId : Maybe String
    , fromLegacy : Bool
    , firstRun : Bool
    }


{-| The preferences a login must preserve. They live in `UserData` for a
logged-in session; this is how they cross the guest boundary.
-}
type alias UserPrefs =
    { shortcutTrayOpen : Bool
    , sortBy : SortBy
    }


defaultPrefs : UserPrefs
defaultPrefs =
    { shortcutTrayOpen = False
    , sortBy = ModifiedAt
    }


type alias UserData =
    { email : String
    , confirmedAt : Maybe Time.Posix
    , shortcutTrayOpen : Bool
    , sortBy : SortBy
    , documents : DocList.Model
    , features : List Feature
    }



-- GETTERS


guestSessionData : Guest -> SessionData
guestSessionData (Guest sessionData _) =
    sessionData


guestPrefs : Guest -> UserPrefs
guestPrefs (Guest _ prefs) =
    prefs


getFromLoggedInSession : (SessionData -> a) -> LoggedIn -> a
getFromLoggedInSession getter (LoggedIn sessionData _) =
    getter sessionData


name : LoggedIn -> String
name (LoggedIn _ { email }) =
    email


lastDocId : LoggedIn -> Maybe String
lastDocId session =
    getFromLoggedInSession .lastDocId session


fromLegacy : Guest -> Bool
fromLegacy (Guest sessionData _) =
    sessionData.fromLegacy


isFirstRun : LoggedIn -> Bool
isFirstRun (LoggedIn sessionData _) =
    sessionData.firstRun


endFirstRun : LoggedIn -> LoggedIn
endFirstRun (LoggedIn sessionData userData) =
    LoggedIn { sessionData | firstRun = False } userData


fileMenuOpen : LoggedIn -> Bool
fileMenuOpen session =
    getFromLoggedInSession .fileMenuOpen session


features : LoggedIn -> List Feature
features (LoggedIn _ userData) =
    userData.features


isNotConfirmed : LoggedIn -> Bool
isNotConfirmed (LoggedIn _ data) =
    data.confirmedAt == Nothing


shortcutTrayOpen : LoggedIn -> Bool
shortcutTrayOpen (LoggedIn _ data) =
    data.shortcutTrayOpen


sortBy : LoggedIn -> SortBy
sortBy (LoggedIn _ data) =
    data.sortBy


documents : LoggedIn -> DocList.Model
documents (LoggedIn _ data) =
    data.documents


copyNaming : LoggedIn -> String -> String
copyNaming (LoggedIn _ data) originalName =
    let
        copyNameRegex =
            Maybe.withDefault Regex.never <|
                Regex.fromString (originalName ++ "\\s*(\\(\\d+\\))?$")
    in
    case data.documents of
        Success docList ->
            docList
                |> List.filter
                    (\d ->
                        d
                            |> Metadata.getDocName
                            |> Maybe.withDefault ""
                            |> Regex.find copyNameRegex
                            |> (not << List.isEmpty)
                    )
                |> List.length
                |> (\n ->
                        if n > 0 then
                            originalName ++ " (" ++ String.fromInt (n + 1) ++ ")"

                        else
                            originalName
                   )

        _ ->
            originalName


getMetadata : LoggedIn -> String -> Maybe Metadata
getMetadata session docId =
    case documents session of
        Success docList ->
            docList
                |> ListExtra.find (\d -> Metadata.getDocId d == docId)

        _ ->
            Nothing


getDocName : LoggedIn -> String -> Maybe String
getDocName session docId =
    getMetadata session docId
        |> Maybe.andThen Metadata.getDocName


isOwner : LoggedIn -> String -> Bool
isOwner session docId =
    getMetadata session docId
        |> Maybe.map Metadata.getCollaborators
        |> Maybe.map (not << List.member (name session))
        |> Maybe.withDefault False



-- UPDATE


sync : Dec.Value -> LoggedIn -> LoggedIn
sync json session =
    let
        settingsDecoder : Decoder { confirmedAt : Maybe Time.Posix }
        settingsDecoder =
            Dec.succeed (\confAt -> { confirmedAt = confAt })
                |> optional "confirmedAt" decodeConfirmedStatus (Just (Time.millisToPosix 0))
    in
    case ( Dec.decodeValue settingsDecoder json, session ) of
        ( Ok newSettings, LoggedIn sessData userData ) ->
            LoggedIn sessData { userData | confirmedAt = newSettings.confirmedAt }

        ( Err _, _ ) ->
            session


setFileOpen : Bool -> LoggedIn -> LoggedIn
setFileOpen isOpen (LoggedIn sessData userData) =
    LoggedIn { sessData | fileMenuOpen = isOpen } userData


{-| Remember which document was open last, both in the session and in storage.
`Page.App.init` reads it back to reopen that document when the app is opened at
`/` (E2), so the two halves are set together, from one value, rather than by
separate call sites that can disagree.

`Nothing` forgets the document — sent when the open document turns out not to
exist, so that `/` does not redirect straight back to it.

-}
storeLastDocId : Maybe String -> LoggedIn -> ( LoggedIn, Cmd msg )
storeLastDocId docId_ (LoggedIn sessData userData) =
    ( LoggedIn { sessData | lastDocId = docId_ } userData
    , send <| SaveUserSetting (lastDocIdSetting docId_)
    )


{-| How the last-opened document is written into the stored session blob: the
key `decoderLoggedIn` reads, and an encoding it can read back (`null` for "no
document", never a missing key, so the write is not a no-op).
-}
lastDocIdSetting : Maybe String -> ( String, Enc.Value )
lastDocIdSetting docId_ =
    ( "lastDocId", Coders.maybeToValue Enc.string docId_ )


confirmEmail : Time.Posix -> LoggedIn -> LoggedIn
confirmEmail currentTime (LoggedIn key data) =
    LoggedIn key { data | confirmedAt = Just currentTime }


setShortcutTrayOpen : Bool -> LoggedIn -> LoggedIn
setShortcutTrayOpen isOpen (LoggedIn key data) =
    LoggedIn key { data | shortcutTrayOpen = isOpen }


setSortBy : SortBy -> LoggedIn -> LoggedIn
setSortBy newSort (LoggedIn sessData userData) =
    LoggedIn sessData { userData | sortBy = newSort }


updateDocuments : DocList.Model -> LoggedIn -> LoggedIn
updateDocuments docList (LoggedIn sessData userData) =
    LoggedIn sessData { userData | documents = DocList.update userData.sortBy docList userData.documents }



-- ENCODER & DECODER


public : Session
public =
    GuestSession (Guest emptySessionData defaultPrefs)


emptySessionData : SessionData
emptySessionData =
    { fileMenuOpen = False
    , lastDocId = Nothing
    , fromLegacy = False
    , firstRun = False
    }


decode : Dec.Value -> Session
decode json =
    case Dec.decodeValue decoderLoggedIn json of
        Ok session ->
            LoggedInSession session

        Err _ ->
            case Dec.decodeValue decoderGuestSession json of
                Ok session ->
                    GuestSession session

                Err _ ->
                    GuestSession (Guest emptySessionData defaultPrefs)


decoderGuestSession : Dec.Decoder Guest
decoderGuestSession =
    Dec.succeed
        (\legacy side lastDoc_ trayOpen sortCriteria ->
            Guest
                { fileMenuOpen = side
                , lastDocId = lastDoc_
                , fromLegacy = legacy
                , firstRun = False
                }
                { shortcutTrayOpen = trayOpen
                , sortBy = sortCriteria
                }
        )
        |> optional "fromLegacy" Dec.bool False
        |> optional "sidebarOpen" Dec.bool False
        |> optional "lastDocId" (Dec.maybe Dec.string) Nothing
        |> optional "shortcutTrayOpen" Dec.bool defaultPrefs.shortcutTrayOpen
        |> optional "sortBy" sortByDecoder defaultPrefs.sortBy


decoderLoggedIn : Dec.Decoder LoggedIn
decoderLoggedIn =
    Dec.succeed
        (\email legacy side confirmTime trayOpen sortCriteria lastDoc_ featList ->
            LoggedIn
                { fileMenuOpen = side
                , lastDocId = lastDoc_
                , fromLegacy = legacy
                , firstRun = False
                }
                (UserData email confirmTime trayOpen sortCriteria DocList.init featList)
        )
        |> required "email" Dec.string
        |> optional "fromLegacy" Dec.bool False
        |> optional "sidebarOpen" Dec.bool False
        |> optional "confirmedAt" decodeConfirmedStatus (Just (Time.millisToPosix 0))
        |> optional "shortcutTrayOpen" Dec.bool defaultPrefs.shortcutTrayOpen
        |> optional "sortBy" sortByDecoder defaultPrefs.sortBy
        |> optional "lastDocId" (Dec.maybe Dec.string) Nothing
        |> optional "features" Features.decoder []


decodeConfirmedStatus : Decoder (Maybe Time.Posix)
decodeConfirmedStatus =
    Dec.oneOf
        [ Dec.null Nothing
        , Dec.int |> Dec.map Time.millisToPosix |> Dec.maybe
        ]


type UserSource
    = FromSignup
    | Other


{-| A logged-in session from what the server answered to a signup, login,
forgotten-password or password-reset request — decoded against the guest
session that made the request, so that preferences the response does not
mention are the ones the user already had, not defaults (E3). `storeLogin`
persists the result, so anything invented here is written over the real thing.

Exposed for the login-decoding tests as well as for the request functions
below.

-}
responseDecoder : UserSource -> Guest -> Dec.Decoder LoggedIn
responseDecoder usrSrc session =
    let
        sessionData =
            guestSessionData session
                |> (\data ->
                        case usrSrc of
                            FromSignup ->
                                { data | firstRun = True }

                            _ ->
                                data
                   )

        storedPrefs =
            guestPrefs session

        builder : String -> Maybe Time.Posix -> Bool -> SortBy -> List Metadata -> List Feature -> LoggedIn
        builder email confAt trayOpen sortCriteria docs feats =
            LoggedIn
                sessionData
                (UserData email confAt trayOpen sortCriteria (DocList.fromList docs) feats)
    in
    Dec.succeed builder
        |> required "email" Dec.string
        |> optional "confirmedAt" decodeConfirmedStatus (Just (Time.millisToPosix 0))
        |> optional "shortcutTrayOpen" Dec.bool storedPrefs.shortcutTrayOpen
        |> optional "sortBy" sortByDecoder storedPrefs.sortBy
        |> optional "documents" Metadata.responseDecoder []
        |> optional "features" Features.decoder []


encodeUserData : UserData -> Enc.Value
encodeUserData userData =
    Enc.object
        [ ( "email", Enc.string userData.email )
        , ( "confirmedAt", userData.confirmedAt |> Maybe.map Time.posixToMillis |> Coders.maybeToValue Enc.int )
        , ( "shortcutTrayOpen", Enc.bool userData.shortcutTrayOpen )
        , ( "sortBy", Coders.sortByEncoder userData.sortBy )
        ]


encode : LoggedIn -> Enc.Value
encode (LoggedIn _ userData) =
    encodeUserData userData



-- AUTHENTICATION


requestSignup : (Result Http.Error LoggedIn -> msg) -> String -> String -> Bool -> Guest -> Cmd msg
requestSignup toMsg email password didOptIn session =
    let
        requestBody =
            Enc.object
                [ ( "email", Enc.string email )
                , ( "password", Enc.string password )
                , ( "subscribed", Enc.bool didOptIn )
                ]
                |> Http.jsonBody
    in
    Http.post
        { url = "/signup"
        , body = requestBody
        , expect = Http.expectJson toMsg (responseDecoder FromSignup session)
        }


storeSignup : LoggedIn -> Cmd msg
storeSignup session =
    store session


requestLogin : (Result Http.Error LoggedIn -> msg) -> String -> String -> Guest -> Cmd msg
requestLogin toMsg email password session =
    let
        requestBody =
            Enc.object
                [ ( "email", Enc.string email )
                , ( "password", Enc.string password )
                ]
                |> Http.jsonBody
    in
    Http.riskyRequest
        { method = "POST"
        , url = "/login"
        , headers = []
        , body = requestBody
        , expect = Http.expectJson toMsg (responseDecoder Other session)
        , timeout = Nothing
        , tracker = Nothing
        }


storeLogin : LoggedIn -> Cmd msg
storeLogin session =
    store session


requestForgotPassword : (Result Http.Error LoggedIn -> msg) -> String -> Guest -> Cmd msg
requestForgotPassword toMsg email session =
    let
        requestBody =
            Enc.object
                [ ( "email", Enc.string email )
                ]
                |> Http.jsonBody
    in
    Http.post
        { url = "/forgot-password"
        , body = requestBody
        , expect = Http.expectJson toMsg (responseDecoder Other session)
        }


requestResetPassword : (Result Http.Error LoggedIn -> msg) -> { newPassword : String, token : String } -> Guest -> Cmd msg
requestResetPassword toMsg { newPassword, token } session =
    let
        requestBody =
            Enc.object
                [ ( "token", Enc.string token )
                , ( "password", Enc.string newPassword )
                ]
                |> Http.jsonBody
    in
    Http.post
        { url = "/reset-password"
        , body = requestBody
        , expect = Http.expectJson toMsg (responseDecoder Other session)
        }


logout : Cmd msg
logout =
    send <| LogoutUser


toGuest : LoggedIn -> Guest
toGuest (LoggedIn sessionData userData) =
    Guest sessionData
        { shortcutTrayOpen = userData.shortcutTrayOpen
        , sortBy = userData.sortBy
        }



-- PORTS


store : LoggedIn -> Cmd msg
store session =
    send <| StoreUser (encode session)


userLoggedIn : msg -> Sub msg
userLoggedIn toMsg =
    userLoggedInMsg (always toMsg)


userLoggedOut : msg -> Sub msg
userLoggedOut toMsg =
    userLoggedOutMsg (always toMsg)


port userLoggedInMsg : (() -> msg) -> Sub msg


port userLoggedOutMsg : (() -> msg) -> Sub msg


port userSettingsChange : (Dec.Value -> msg) -> Sub msg
