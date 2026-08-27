port module Session exposing (Guest, LoggedIn, Session(..), UserSource(..), confirmEmail, copyNaming, decode, documents, endFirstRun, features, fileMenuOpen, fromLegacy, getDocName, getMetadata, isFirstRun, isNotConfirmed, encode, isOwner, lastDocId, lastDocIdSetting, logout, name, public, requestLogin, requestSignup, responseDecoder, setFileOpen, setShortcutTrayOpen, setSortBy, shortcutTrayOpen, signupBody, sortBy, storeLastDocId, storeLogin, storeSignup, sync, toGuest, updateDocuments, userLoggedIn, userLoggedOut, userSettingsChange)

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


type Guest
    = Guest SessionData


type LoggedIn
    = LoggedIn SessionData UserData


{-| What this browser knows about the session, whether or not anyone is logged
in: the preferences the user set here, and where they were. All of it is
persisted (in the session blob Elm's flags are decoded from) and none of it
comes from the server, which is why it survives a logout and a login -- the
guest session carries it across, so logging back in cannot reset it (E3).
-}
type alias SessionData =
    { fileMenuOpen : Bool
    , lastDocId : Maybe String
    , shortcutTrayOpen : Bool
    , sortBy : SortBy
    , fromLegacy : Bool
    , firstRun : Bool
    }


{-| Who is logged in, as the server describes them.
-}
type alias UserData =
    { email : String
    , confirmedAt : Maybe Time.Posix
    , documents : DocList.Model
    , features : List Feature
    }



-- GETTERS


guestSessionData : Guest -> SessionData
guestSessionData (Guest sessionData) =
    sessionData


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
fromLegacy (Guest sessionData) =
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
shortcutTrayOpen session =
    getFromLoggedInSession .shortcutTrayOpen session


sortBy : LoggedIn -> SortBy
sortBy session =
    getFromLoggedInSession .sortBy session


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
setShortcutTrayOpen isOpen (LoggedIn sessData userData) =
    LoggedIn { sessData | shortcutTrayOpen = isOpen } userData


setSortBy : SortBy -> LoggedIn -> LoggedIn
setSortBy newSort (LoggedIn sessData userData) =
    LoggedIn { sessData | sortBy = newSort } userData


updateDocuments : DocList.Model -> LoggedIn -> LoggedIn
updateDocuments docList (LoggedIn sessData userData) =
    LoggedIn sessData { userData | documents = DocList.update sessData.sortBy docList userData.documents }



-- ENCODER & DECODER


public : Session
public =
    GuestSession (Guest emptySessionData)


{-| A session nobody has set anything in yet: the defaults every decoder falls
back to, in one place.
-}
emptySessionData : SessionData
emptySessionData =
    { fileMenuOpen = False
    , lastDocId = Nothing
    , shortcutTrayOpen = False
    , sortBy = ModifiedAt
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
                    GuestSession (Guest emptySessionData)


decoderGuestSession : Dec.Decoder Guest
decoderGuestSession =
    Dec.succeed
        (\legacy side lastDoc_ trayOpen sortCriteria ->
            Guest
                { fileMenuOpen = side
                , lastDocId = lastDoc_
                , shortcutTrayOpen = trayOpen
                , sortBy = sortCriteria
                , fromLegacy = legacy
                , firstRun = False
                }
        )
        |> optional "fromLegacy" Dec.bool False
        |> optional "sidebarOpen" Dec.bool emptySessionData.fileMenuOpen
        |> optional "lastDocId" (Dec.maybe Dec.string) emptySessionData.lastDocId
        |> optional "shortcutTrayOpen" Dec.bool emptySessionData.shortcutTrayOpen
        |> optional "sortBy" sortByDecoder emptySessionData.sortBy


decoderLoggedIn : Dec.Decoder LoggedIn
decoderLoggedIn =
    Dec.succeed
        (\email legacy side confirmTime trayOpen sortCriteria lastDoc_ featList ->
            LoggedIn
                { fileMenuOpen = side
                , lastDocId = lastDoc_
                , shortcutTrayOpen = trayOpen
                , sortBy = sortCriteria
                , fromLegacy = legacy
                , firstRun = False
                }
                (UserData email confirmTime DocList.init featList)
        )
        |> required "email" Dec.string
        |> optional "fromLegacy" Dec.bool False
        |> optional "sidebarOpen" Dec.bool emptySessionData.fileMenuOpen
        |> optional "confirmedAt" decodeConfirmedStatus (Just (Time.millisToPosix 0))
        |> optional "shortcutTrayOpen" Dec.bool emptySessionData.shortcutTrayOpen
        |> optional "sortBy" sortByDecoder emptySessionData.sortBy
        |> optional "lastDocId" (Dec.maybe Dec.string) emptySessionData.lastDocId
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


{-| A logged-in session from what the server answered to a signup or login
request — decoded against the guest session that made the request, so that
preferences the response does not mention are the ones the user already had,
not defaults (E3). `storeLogin` persists the result, so anything invented here
is written over the real thing.

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

        builder : String -> Maybe Time.Posix -> Bool -> SortBy -> List Metadata -> List Feature -> LoggedIn
        builder email confAt trayOpen sortCriteria docs feats =
            LoggedIn
                { sessionData | shortcutTrayOpen = trayOpen, sortBy = sortCriteria }
                (UserData email confAt (DocList.fromList docs) feats)
    in
    Dec.succeed builder
        |> required "email" Dec.string
        |> optional "confirmedAt" decodeConfirmedStatus (Just (Time.millisToPosix 0))
        |> optional "shortcutTrayOpen" Dec.bool sessionData.shortcutTrayOpen
        |> optional "sortBy" sortByDecoder sessionData.sortBy
        |> optional "documents" Metadata.responseDecoder []
        |> optional "features" Features.decoder []


{-| The stored session blob, as `StoreUser` writes it. That write replaces the
blob wholesale, so every preference `decoderLoggedIn` reads has to be here or
logging in would forget it.
-}
encode : LoggedIn -> Enc.Value
encode (LoggedIn sessData userData) =
    Enc.object
        [ ( "email", Enc.string userData.email )
        , ( "confirmedAt", userData.confirmedAt |> Maybe.map Time.posixToMillis |> Coders.maybeToValue Enc.int )
        , ( "shortcutTrayOpen", Enc.bool sessData.shortcutTrayOpen )
        , ( "sortBy", Coders.sortByEncoder sessData.sortBy )
        , ( "sidebarOpen", Enc.bool sessData.fileMenuOpen )
        , lastDocIdSetting sessData.lastDocId
        ]



-- AUTHENTICATION


{-| Everything the client asks a self-hosted server to create an account with.

There was a third field, carrying a mailing-list opt-in from a checkbox on the
signup form. A self-hosted server has no mailing list to add anyone to, so the
field and the checkbox are both gone (A4).

-}
signupBody : String -> String -> Enc.Value
signupBody email password =
    Enc.object
        [ ( "email", Enc.string email )
        , ( "password", Enc.string password )
        ]


requestSignup : (Result Http.Error LoggedIn -> msg) -> String -> String -> Guest -> Cmd msg
requestSignup toMsg email password session =
    Http.post
        { url = "/signup"
        , body = signupBody email password |> Http.jsonBody
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


logout : Cmd msg
logout =
    send <| LogoutUser


toGuest : LoggedIn -> Guest
toGuest (LoggedIn sessionData _) =
    Guest sessionData



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
