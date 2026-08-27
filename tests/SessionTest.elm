module SessionTest exposing (loginResponse, preferences, sidebar, suite)

{-| Tests at the ADR-0002 seam: `Session.decode` on the stored user data that
`StoreUser` persists to localStorage.

A self-hosted user is never blocked from editing by account age. ADR-0002
removed the trial clock itself, so what is left to pin here is that stored data
written by an older build — which still carries a `paymentStatus` string, and a
trial expiry inside it — stays inert: the leftover field is ignored, and it is
never fatal to the decode (a failed logged-in decode silently demotes the user
to a guest session, i.e. logs them out).

-}

import Expect
import Json.Decode as Dec
import Json.Encode as Enc
import Page.App
import Session
import Test exposing (Test, describe, test)
import Types exposing (SortBy(..))


bootTimeMillis : Int
bootTimeMillis =
    1700000000000


{-| Stored user data as it reaches `Session.decode` on boot: what
`StoreUser` wrote to localStorage, plus the `currentTime` the JS layer
merges in.
-}
storedUser : List ( String, Enc.Value ) -> Enc.Value
storedUser extraFields =
    Enc.object
        ([ ( "email", Enc.string "user@example.com" )
         , ( "currentTime", Enc.int bootTimeMillis )
         , ( "shortcutTrayOpen", Enc.bool True )
         ]
            ++ extraFields
        )


decodeLoggedIn : Enc.Value -> Result String Session.LoggedIn
decodeLoggedIn json =
    case Session.decode json of
        Session.LoggedInSession loggedIn ->
            Ok loggedIn

        Session.GuestSession _ ->
            Err "expected a logged-in session, got a guest session"


{-| The observable state of a decoded logged-in session. Stale trial fields in
the stored data must not change any of it.
-}
observable : Session.LoggedIn -> { email : String, shortcutTrayOpen : Bool }
observable loggedIn =
    { email = Session.name loggedIn
    , shortcutTrayOpen = Session.shortcutTrayOpen loggedIn
    }


expectSameAsClean : Enc.Value -> Expect.Expectation
expectSameAsClean json =
    case ( decodeLoggedIn json, decodeLoggedIn (storedUser []) ) of
        ( Ok withStale, Ok clean ) ->
            observable withStale |> Expect.equal (observable clean)

        ( Err err, _ ) ->
            Expect.fail err

        ( _, Err err ) ->
            Expect.fail err


suite : Test
suite =
    describe "Session, stored user data"
        [ test "stored data with no payment status decodes a logged-in session" <|
            \_ ->
                decodeLoggedIn (storedUser [])
                    |> Result.map observable
                    |> Expect.equal
                        (Ok { email = "user@example.com", shortcutTrayOpen = True })
        , test "a stale persisted trial expiry is ignored" <|
            \_ ->
                expectSameAsClean (storedUser [ ( "paymentStatus", Enc.string "trial:1" ) ])
        , test "a stale customer payment status is ignored" <|
            \_ ->
                expectSameAsClean (storedUser [ ( "paymentStatus", Enc.string "customer:cus_1" ) ])
        , test "an unparseable stale payment status is ignored, not fatal" <|
            \_ ->
                expectSameAsClean (storedUser [ ( "paymentStatus", Enc.string "trial-expired-2019" ) ])
        ]


{-| Ticket 13: the three preferences that reach `Session` as stored JSON —
which document was open last, whether the shortcut tray is open, and how the
document list is sorted. Every one of them is written by one path and read
back by another, so they are pinned at the decode seam.
-}
preferences : Test
preferences =
    describe "Session, stored preferences"
        [ test "the last opened document is remembered, so / can reopen it" <|
            \_ ->
                decodeLoggedIn (storedUser [ ( "lastDocId", Enc.string "tree-abc" ) ])
                    |> Result.map Session.lastDocId
                    |> Expect.equal (Ok (Just "tree-abc"))
        , test "stored data with no last document has none to reopen" <|
            \_ ->
                decodeLoggedIn (storedUser [])
                    |> Result.map Session.lastDocId
                    |> Expect.equal (Ok Nothing)
        , test "opening a document writes it back as the one to reopen" <|
            \_ ->
                decodeLoggedIn (storedUser [ Session.lastDocIdSetting (Just "tree-xyz") ])
                    |> Result.map Session.lastDocId
                    |> Expect.equal (Ok (Just "tree-xyz"))
        , test "forgetting the last document writes null, which is read back as none, not as a broken session" <|
            \_ ->
                decodeLoggedIn (storedUser [ Session.lastDocIdSetting Nothing ])
                    |> Result.map (\session -> ( Session.name session, Session.lastDocId session ))
                    |> Expect.equal (Ok ( "user@example.com", Nothing ))
        ]


{-| Ticket 13: the sidebar's state is a preference too, but it is written by
`Page.App` — into the session (which every re-init of the page reads back, and
the loading spinner with it) and into storage, from this one flag.
-}
sidebar : Test
sidebar =
    describe "The sidebar's recorded state"
        [ test "an open sidebar is recorded as open" <|
            \_ ->
                Page.App.sidebarIsOpen Page.App.File
                    |> Expect.equal True
        , test "a closed sidebar is recorded as closed" <|
            \_ ->
                Page.App.sidebarIsOpen Page.App.SidebarClosed
                    |> Expect.equal False
        ]


{-| A stored session for a user who left the shortcut tray closed and the
document list sorted alphabetically. Neither is the default, so a login that
resets them is visible.
-}
storedWithPrefs : Enc.Value
storedWithPrefs =
    Enc.object
        [ ( "email", Enc.string "user@example.com" )
        , ( "shortcutTrayOpen", Enc.bool False )
        , ( "sortBy", Enc.string "Alphabetical" )
        ]


{-| The guest session a logged-in user becomes on the way to the login screen
(`Main.UserLoggedOut` → `Session.toGuest` → `Page.Login`), which is the session
the login request decodes its response against.
-}
guestFrom : Enc.Value -> Result String Session.Guest
guestFrom stored =
    decodeLoggedIn stored |> Result.map Session.toGuest


{-| Log in as that guest, with what the server answered. -}
logIn : Result String Session.Guest -> List ( String, Enc.Value ) -> Result String ( Bool, SortBy )
logIn guest_ responseFields =
    guest_
        |> Result.andThen
            (\guest ->
                Enc.object (( "email", Enc.string "user@example.com" ) :: responseFields)
                    |> Dec.decodeValue (Session.responseDecoder Session.Other guest)
                    |> Result.mapError Dec.errorToString
            )
        |> Result.map (\session -> ( Session.shortcutTrayOpen session, Session.sortBy session ))


{-| Ticket 13 / E3: logging in used to hand back a session with the shortcut
tray open and the document list sorted by modification date, whatever the user
had chosen — and `storeLogin` then wrote those defaults over the real ones.
-}
loginResponse : Test
loginResponse =
    describe "Session, logging in"
        [ test "a response that says nothing about the preferences keeps them" <|
            \_ ->
                logIn (guestFrom storedWithPrefs) []
                    |> Expect.equal (Ok ( False, Alphabetical ))
        , test "a response that carries preferences is believed" <|
            \_ ->
                logIn (guestFrom storedWithPrefs)
                    [ ( "shortcutTrayOpen", Enc.bool True )
                    , ( "sortBy", Enc.string "CreatedAt" )
                    ]
                    |> Expect.equal (Ok ( True, CreatedAt ))
        ]
