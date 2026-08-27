module SessionTest exposing (copyNaming, loginResponse, ownership, preferences, sidebar, suite)

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
        , test "storing the whole session, as logging in does, keeps every preference" <|
            \_ ->
                expectSurvivesStoring
                    (storedUser
                        [ ( "shortcutTrayOpen", Enc.bool False )
                        , ( "sortBy", Enc.string "Alphabetical" )
                        , ( "sidebarOpen", Enc.bool True )
                        , Session.lastDocIdSetting (Just "tree-abc")
                        ]
                    )
        ]


{-| Everything about a session that the user chose, and that reading the stored
blob back therefore has to return.
-}
chosenPreferences :
    Session.LoggedIn
    ->
        { shortcutTrayOpen : Bool
        , sortBy : SortBy
        , sidebarOpen : Bool
        , lastDocId : Maybe String
        }
chosenPreferences session =
    { shortcutTrayOpen = Session.shortcutTrayOpen session
    , sortBy = Session.sortBy session
    , sidebarOpen = Session.fileMenuOpen session
    , lastDocId = Session.lastDocId session
    }


{-| `StoreUser` — which `storeLogin` and `storeSignup` send — replaces the
stored blob with `Session.encode`'s output, so a preference the encoder leaves
out is a preference logging in forgets.
-}
expectSurvivesStoring : Enc.Value -> Expect.Expectation
expectSurvivesStoring stored =
    let
        reStored =
            decodeLoggedIn stored
                |> Result.map Session.encode
                |> Result.andThen decodeLoggedIn
    in
    case ( decodeLoggedIn stored, reStored ) of
        ( Ok asStored, Ok asReStored ) ->
            chosenPreferences asReStored
                |> Expect.equal (chosenPreferences asStored)

        ( Err err, _ ) ->
            Expect.fail err

        ( _, Err err ) ->
            Expect.fail err


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
                    |> Dec.decodeValue (Session.responseDecoder guest)
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



-- === WHAT THE SESSION SAYS ABOUT A DOCUMENT (ADR-0001 seam 13) ===


{-| One row of the document list, in the shape the server answers with
(`Doc.Metadata.responseDecoder`).
-}
docRow : { id : String, name : String, collaborators : List String } -> Enc.Value
docRow { id, name, collaborators } =
    Enc.object
        [ ( "id", Enc.string id )
        , ( "name", Enc.string name )
        , ( "collaborators", Enc.list Enc.string collaborators )
        , ( "createdAt", Enc.int bootTimeMillis )
        , ( "updatedAt", Enc.int bootTimeMillis )
        ]


{-| A logged-in session whose document list has arrived, holding these
documents. Built through `responseDecoder`, which is how a real list reaches the
session — `Session.updateDocuments` takes the same `DocList.Success`.
-}
withDocuments :
    List { id : String, name : String, collaborators : List String }
    -> Result String Session.LoggedIn
withDocuments docs =
    sessionStillLoading
        |> Result.map Session.toGuest
        |> Result.andThen
            (\guest ->
                Enc.object
                    [ ( "email", Enc.string "user@example.com" )
                    , ( "documents", Enc.list docRow docs )
                    ]
                    |> Dec.decodeValue (Session.responseDecoder guest)
                    |> Result.mapError Dec.errorToString
            )


{-| A session as it is for the first moments of every boot: logged in, document
list still on its way (`DocList.init`).
-}
sessionStillLoading : Result String Session.LoggedIn
sessionStillLoading =
    decodeLoggedIn (storedUser [])


{-| Named documents, with no collaborators — the shape every copy-naming case
below only cares about the names of.
-}
named : List String -> Result String Session.LoggedIn
named names =
    names
        |> List.indexedMap
            (\i docName ->
                { id = "doc-" ++ String.fromInt i, name = docName, collaborators = [] }
            )
        |> withDocuments


{-| The copy name a session hands out for a document called `originalName`. -}
copyOf : String -> Result String Session.LoggedIn -> Result String String
copyOf originalName =
    Result.map (\session -> Session.copyNaming session originalName)


{-| What a session says about who owns `docId`. -}
ownerOf : String -> Result String Session.LoggedIn -> Result String Session.Ownership
ownerOf docId =
    Result.map (\session -> Session.ownership session docId)


{-| S4: the name a copy of a document gets. It used to be decided by a regex
built from the document's own name — unescaped, and anchored only at the end —
so a name with a metacharacter in it fell back to `Regex.never` (the copy kept
the colliding name), `"Doc"` also counted `"My Doc"`, and counting matches
rather than looking for a free number handed out a name that was already taken.
-}
copyNaming : Test
copyNaming =
    describe "Naming the copy of a document"
        [ test "a name nothing in the list holds is used as it is" <|
            \_ ->
                named [ "Some other document" ]
                    |> copyOf "Report"
                    |> Expect.equal (Ok "Report")
        , test "the first copy of a document is numbered 2" <|
            \_ ->
                named [ "Report" ]
                    |> copyOf "Report"
                    |> Expect.equal (Ok "Report (2)")
        , test "the next copy takes the next number" <|
            \_ ->
                named [ "Report", "Report (2)" ]
                    |> copyOf "Report"
                    |> Expect.equal (Ok "Report (3)")
        , test "a name with a regex metacharacter in it is still copied" <|
            \_ ->
                -- An unbalanced paren made `Regex.fromString` fail, and
                -- `Regex.never` matched nothing: the copy kept the exact name
                -- of the document it was copied from.
                named [ "Notes (draft" ]
                    |> copyOf "Notes (draft"
                    |> Expect.equal (Ok "Notes (draft (2)")
        , test "a metacharacter matches itself, not any character" <|
            \_ ->
                -- `.` in an unescaped regex matched the space in "My Doc", so a
                -- name nobody had used was numbered as though it were taken.
                named [ "My Doc" ]
                    |> copyOf "My.Doc"
                    |> Expect.equal (Ok "My.Doc")
        , test "a document whose name ends with the copied one is not a copy of it" <|
            \_ ->
                named [ "My Doc", "Doc" ]
                    |> copyOf "Doc"
                    |> Expect.equal (Ok "Doc (2)")
        , test "a gap in the numbering is filled rather than collided with" <|
            \_ ->
                named [ "Doc", "Doc (3)" ]
                    |> copyOf "Doc"
                    |> Expect.equal (Ok "Doc (2)")
        , test "a full run of numbers is continued past the end" <|
            \_ ->
                named [ "Doc", "Doc (2)", "Doc (3)" ]
                    |> copyOf "Doc"
                    |> Expect.equal (Ok "Doc (4)")
        , test "with the list still loading the name is left alone" <|
            \_ ->
                sessionStillLoading
                    |> copyOf "Report"
                    |> Expect.equal (Ok "Report")
        ]


{-| S3: who owns the document on screen. The client learns this only from the
document list, so for the first moments of every boot there is no answer — and
answering "not the owner" there made the owner-only chrome (the title field, the
sidebar's Delete) flap into place a moment later.
-}
ownership : Test
ownership =
    describe "Who owns a document"
        [ test "a document in my list that I am not a collaborator on is mine" <|
            \_ ->
                withDocuments [ { id = "doc-1", name = "Report", collaborators = [] } ]
                    |> ownerOf "doc-1"
                    |> Expect.equal (Ok Session.Owner)
        , test "a document I am a collaborator on is not mine" <|
            \_ ->
                withDocuments
                    [ { id = "doc-1", name = "Report", collaborators = [ "user@example.com" ] } ]
                    |> ownerOf "doc-1"
                    |> Expect.equal (Ok Session.NotOwner)
        , test "someone else being a collaborator says nothing about me" <|
            \_ ->
                withDocuments
                    [ { id = "doc-1", name = "Report", collaborators = [ "someone@example.com" ] } ]
                    |> ownerOf "doc-1"
                    |> Expect.equal (Ok Session.Owner)
        , test "a document my list has answered and does not hold is not mine" <|
            \_ ->
                withDocuments [ { id = "doc-1", name = "Report", collaborators = [] } ]
                    |> ownerOf "someone-elses-doc"
                    |> Expect.equal (Ok Session.NotOwner)
        , test "while the list is still loading there is no answer, not a no" <|
            \_ ->
                sessionStillLoading
                    |> ownerOf "doc-1"
                    |> Expect.equal (Ok Session.Unknown)
        ]
