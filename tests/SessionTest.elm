module SessionTest exposing (preferences, sidebar, suite)

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
