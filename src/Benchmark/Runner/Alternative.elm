module Benchmark.Runner.Alternative exposing
    ( Program, program
    , programWith, Options, defaultOptions, Theme, darkTheme, lightTheme
    , Context
    , progressBenchmark
    )

{-| Run benchmarks in the browser.

`import Benchmark.Runner.Alternative as BenchmarkRunner`.

@docs Program, program


## options

@docs programWith, Options, defaultOptions, Theme, darkTheme, lightTheme


### to write a custom render function

@docs Context


## to write your own runner

@docs progressBenchmark

-}

import Benchmark exposing (Benchmark)
import Benchmark.Reporting as Report
import Benchmark.Status.Alternative as Status exposing (Running(..), Status(..), StructureKind(..), runsPerSecond, secondsPerRun)
import Browser
import Color exposing (Color, rgb)
import Element.WithContext as Ui
import Element.WithContext.Background as Background
import Element.WithContext.Font as Font
import Humanize as Humanize
import Process
import Task exposing (Task)
import Trend.Linear as Trend exposing (Quick, Trend)


type alias Model =
    { suite : Benchmark
    }


{-| A benchmark runner program. See [`program`](#program) for how to create one.
-}
type alias Program =
    Platform.Program () Model Msg


{-| Run benchmarks with [`defaultOptions`](#defaultOptions).

    main =
        BenchmarkRunner.program suite

-}
program : Benchmark -> Program
program suite =
    programWith defaultOptions suite


{-| Run benchmarks with custom [`Options`](#Options).

    main =
        programWith { defaultOptions | theme = Light }

-}
programWith : Options -> Benchmark -> Program
programWith options suite =
    Browser.document
        { init =
            \_ ->
                ( { suite = suite }
                , Task.succeed suite
                    |> Task.perform BenchmarkProgress
                )
        , update = update
        , subscriptions = \_ -> Sub.none
        , view = viewDocument options
        }


{-| Options to start the [`BenchmarkProgram`](Benchmark.Runner.Alternative#BenchmarkProgram) with:


#### `theme`

[`Theme`](#Theme).


#### `view`

Write a custom renderer. The theme's background and foreground colors are already set.

    import Benchmark.Runner.Alternative as BenchmarkRunner exposing (defaultOptions)
    import Benchmark.Status.Alternative exposing (Status(..), StructureKind(..))
    import Element.WithContext as Ui

    main =
        BenchmarkRunner.programWith
            { defaultOptions | view = view }
            suite

    view status =
        case status of
            Running _ _ ->
                Ui.text "running benchmarks..."

            Finished finished ->
                viewFinished finished status.name

    viewFinished finished =
        case finished.structure of
            Group group ->
                Ui.column [ Ui.spacing 6 ]
                    [ Ui.text finished.name
                    , Ui.column [ Ui.spacing 4 ]
                        (group |> List.map viewFinished)
                    ]

            Single { result } ->
                case result of
                    Ok trend ->
                        Ui.row [ Ui.spacing 6 ]
                            [ Ui.text finished.name
                            , Ui.text
                                (runsPerSecond trend
                                    |> String.fromFloat
                                )
                            ]

                    Err _ ->
                        Ui.text "Failed!"

            ...

-}
type alias Options =
    { theme : Theme
    , view : Status -> Ui.Element Context Msg
    }


{-| The context of the runner's ui, containing the `theme`.
-}
type alias Context =
    { theme : Theme
    }


{-| `{ theme = darkTheme }` and default rendering.
-}
defaultOptions : Options
defaultOptions =
    { theme = darkTheme
    , view = view
    }


{-| Color theme.
Defaults are [`darkTheme`](#darkTheme) and [`lightTheme`](#lightTheme).
-}
type alias Theme =
    { background : Color
    , foreground : Color
    }


{-| White stuff on a black background.
-}
darkTheme : Theme
darkTheme =
    { background = rgb 0 0 0
    , foreground = rgb 1 1 1
    }


{-| Black stuff on a white background.
-}
lightTheme : Theme
lightTheme =
    { background = rgb 1 1 1
    , foreground = rgb 0 0 0
    }


type Msg
    = BenchmarkProgress Benchmark


update : Msg -> Model -> ( Model, Cmd Msg )
update (BenchmarkProgress updatedSuite) model =
    ( { model | suite = updatedSuite }
    , progressBenchmark updatedSuite
    )


breakForRender : Task x a -> Task x a
breakForRender task =
    Task.andThen (\_ -> task) (Process.sleep 0)


{-| `Benchmark.step` if the benchmark still hasn't received all results.
-}
progressBenchmark : Benchmark -> Cmd Msg
progressBenchmark benchmark =
    if Benchmark.done benchmark then
        Cmd.none

    else
        Benchmark.step benchmark
            |> breakForRender
            |> Task.perform BenchmarkProgress


viewDocument : Options -> Model -> Browser.Document Msg
viewDocument { theme } { suite } =
    { title = "benchmarks"
    , body =
        [ let
            suiteReport =
                suite |> Report.fromBenchmark |> Status.fromReport
          in
          view suiteReport
            |> Ui.layout
                { theme = theme }
                [ Ui.withAttribute (.theme >> .background)
                    (Background.color << toUiColor)
                , Ui.withAttribute (.theme >> .foreground)
                    (Font.color << toUiColor)
                ]
        ]
    }


view : Status -> Ui.Element Context msg_
view status =
    [ [ "benchmark report"
            |> Ui.text
            |> Ui.el [ Font.size 29 ]
      , case status of
            Status.Running running _ ->
                viewRunningStatus running

            Status.Finished _ ->
                Ui.none
      ]
        |> Ui.column [ Ui.spacing 5 ]
    , viewStructure status
    ]
        |> Ui.column
            [ Ui.paddingXY 40 45
            , Ui.spacing 20
            ]


viewStructure : Status -> Ui.Element Context msg_
viewStructure status =
    case status of
        Running _ running ->
            viewRunningStructure running

        Finished finished ->
            [ let
                minimumGoodnessOfFit =
                    lowestGoodnessOfFit finished
              in
              if minimumGoodnessOfFit < 0.85 then
                [ "There is high interference on the system."
                , " Don't trust these results."
                , " Close resource-intensive tabs or programs (Slack, Spotify are typical candidates) and run again."
                , [ " If that doesn't solve it, show up in #elm-benchmark on the Elm Slack and we'll try to get you sorted out."
                  , " There's probably some error this tool can't detect, or we need to account for your system setup in the sampling approach."
                  ]
                    |> String.concat
                ]
                    |> List.map (Ui.paragraph [] << List.singleton << Ui.text)
                    |> Ui.column [ Ui.spacing 13 ]

              else if minimumGoodnessOfFit < 0.95 then
                [ "There may be interference on the system."
                , " Consider closing resource-intensive programs (Slack, Spotify are typical candidates) or tabs and run again."
                ]
                    |> List.map (Ui.paragraph [] << List.singleton << Ui.text)
                    |> Ui.column [ Ui.spacing 13 ]

              else
                Ui.none
            , viewFinishedStructure finished
            ]
                |> Ui.column [ Ui.spacing 20 ]


viewRunningStatus : Status.Running -> Ui.Element Context msg_
viewRunningStatus runningStatus =
    let
        viewInfo info =
            info
                |> Ui.text
                |> Ui.el [ Font.size 18 ]
    in
    case runningStatus of
        WarmingJit ->
            "Warming JIT" |> viewInfo

        FindingSampleSize ->
            "Finding sample size" |> viewInfo

        CollectingSamples progress ->
            [ "collecting samples" |> viewInfo
            , progress
                |> viewRelation
                    [ Ui.width (Ui.px 111), Ui.height Ui.fill ]
            ]
                |> Ui.row [ Ui.spacing 10 ]


{-| Find the lowest goodness of fit.
Return `1` if all benchmarks have failed or no actual benchmarks exist (only empty groups & series).
-}
lowestGoodnessOfFit : Status.Structure { result : Status.Result } -> Float
lowestGoodnessOfFit finished =
    case finished.structureKind of
        Single { result } ->
            result
                |> Result.map Trend.goodnessOfFit
                |> Result.withDefault 1

        Group group ->
            group
                |> List.map lowestGoodnessOfFit
                |> List.minimum
                |> Maybe.withDefault 1

        Series series ->
            series
                |> List.filterMap
                    (.result
                        >> Result.map (Trend.goodnessOfFit >> Just)
                        >> Result.withDefault Nothing
                    )
                |> List.minimum
                |> Maybe.withDefault 1


viewFinishedStructure :
    Status.Structure { result : Status.Result }
    -> Ui.Element Context msg_
viewFinishedStructure finished =
    case finished.structureKind of
        Group group ->
            viewGroup finished.name
                (group |> List.map viewFinishedStructure)

        Single status ->
            viewFinishedSingle finished.name status.result

        Series series ->
            viewFinishedSeries finished.name series


viewRunningStructure : Status.Structure {} -> Ui.Element Context msg_
viewRunningStructure running =
    case running.structureKind of
        Group group ->
            viewGroup running.name
                (group |> List.map viewRunningStructure)

        Single _ ->
            viewRunningSingle running.name

        Series series ->
            viewRunningSeries running.name series


viewRunningSingle : String -> Ui.Element context_ msg_
viewRunningSingle name =
    viewHeadline name
        |> Ui.el [ Ui.paddingXY 0 4 ]


viewFinishedSingle : String -> Status.Result -> Ui.Element context_ msg_
viewFinishedSingle name finished =
    let
        viewSuccess trend =
            { data = [ { trend = trend } ] -- 1 row below the headers
            , columns =
                [ { header = Ui.none
                  , width = Ui.shrink
                  , view =
                        \_ ->
                            name
                                |> viewHeadline
                                |> Ui.el [ Ui.centerY ]
                  }
                , viewRunsPerSecondColumn
                , goodnessOfFitColumn
                ]
            }
                |> Ui.table [ Ui.spacingXY 16 4, Ui.paddingXY 0 4 ]

        viewFailure =
            [ name |> viewHeadline
            , "Failed" |> Ui.text
            ]
                |> Ui.row [ Ui.spacingXY 16 0 ]
    in
    finished
        |> Result.map viewSuccess
        |> Result.withDefault viewFailure


viewGroup :
    String
    -> List (Ui.Element Context msg)
    -> Ui.Element Context msg
viewGroup name structures =
    [ name |> viewHeadline
    , structures
        |> Ui.column
            [ Ui.paddingEach { edges | left = 26 }
            , Ui.spacing 13
            ]
    ]
        |> Ui.column [ Ui.spacing 12 ]


viewFinishedSeries :
    String
    -> List { name : String, result : Status.Result }
    -> Ui.Element Context msg_
viewFinishedSeries name series =
    let
        successes =
            series
                |> List.filterMap
                    (\sub ->
                        case sub.result of
                            Ok trend ->
                                Just { name = sub.name, trend = trend }

                            Err _ ->
                                Nothing
                    )
                |> List.sortBy (.trend >> secondsPerRun)

        failures =
            series
                |> List.filterMap
                    (\sub ->
                        case sub.result of
                            Err _ ->
                                Just sub.name

                            Ok _ ->
                                Nothing
                    )
    in
    [ { data = successes
      , columns =
            [ { header = name |> viewHeadline
              , width = Ui.shrink
              , view =
                    \sub ->
                        sub.name
                            |> Ui.text
                            |> Ui.el [ Ui.centerY ]
              }
            , let
                maxSecondPerRun =
                    List.maximum
                        (successes
                            |> List.map (.trend >> secondsPerRun)
                        )
                        |> Maybe.withDefault 0
              in
              { header = "time / run" |> viewInfoHeader
              , width = Ui.minimum 129 Ui.shrink
              , view =
                    \{ trend } ->
                        (secondsPerRun trend / maxSecondPerRun)
                            |> viewRelation
                                [ Ui.width Ui.fill, Ui.height Ui.fill ]
              }
            , viewRunsPerSecondColumn
            , goodnessOfFitColumn
            ]
      }
        |> Ui.table [ Ui.spacingXY 16 6 ]
    , { data = failures
      , columns =
            [ \subName -> subName |> Ui.text
            , \_ -> "Failed" |> Ui.text
            ]
                |> List.map
                    (\view_ ->
                        { header = Ui.none
                        , width = Ui.shrink
                        , view = view_
                        }
                    )
      }
        |> Ui.table [ Ui.spacingXY 16 6 ]
    ]
        |> Ui.row []


viewRunningSeries :
    String
    -> List { name : String }
    -> Ui.Element context_ msg_
viewRunningSeries name series =
    [ viewHeadline name
    , series
        |> List.map (.name >> Ui.text)
        |> Ui.column [ Ui.paddingXY 20 0 ]
    ]
        |> Ui.column [ Ui.spacing 8 ]


viewRunsPerSecondColumn : Ui.Column context_ { record | trend : Trend Quick } msg_
viewRunsPerSecondColumn =
    { header = "runs / second" |> viewInfoHeader
    , width = Ui.shrink
    , view =
        \{ trend } ->
            runsPerSecond trend
                |> floor
                |> Humanize.int
                |> Ui.text
    }


goodnessOfFitColumn : Ui.Column context_ { record | trend : Trend Quick } msg_
goodnessOfFitColumn =
    { header = "goodness of fit" |> viewInfoHeader
    , width = Ui.shrink
    , view =
        \{ trend } ->
            -- https://package.elm-lang.org/packages/elm-explorations/benchmark/latest#faq
            let
                goodnessOfFit =
                    Trend.goodnessOfFit trend

                goodnessOfFitPercent =
                    goodnessOfFit |> Humanize.percent
            in
            if goodnessOfFit < 0.85 then
                [ goodnessOfFitPercent
                , ", highly influenced"
                ]
                    |> String.concat
                    |> Ui.text

            else if goodnessOfFit < 0.95 then
                [ goodnessOfFitPercent
                , ", slightly influenced"
                ]
                    |> String.concat
                    |> Ui.text

            else
                goodnessOfFitPercent
                    |> Ui.text
                    |> Ui.el [ Ui.alpha 0.7 ]
    }


{-| View a percentage as a horizontal bar. The argument must be between 0 and 1.

    halfHalf =
        0.5 |> viewRelation [ width fill, height fill ]

-}
viewRelation :
    List (Ui.Attribute Context msg)
    -> Float
    -> Ui.Element Context msg
viewRelation attrs percent =
    let
        per100 =
            percent * 100 |> floor

        bar width barAttrs =
            Ui.el
                ([ Ui.withAttribute (.theme >> .foreground)
                    (Background.color << toUiColor)
                 , Ui.height Ui.fill
                 , Ui.width width
                 ]
                    ++ barAttrs
                )
                Ui.none
    in
    [ bar (Ui.fillPortion per100) [ Ui.alpha 0.58 ]
    , bar (Ui.fillPortion (100 - per100)) [ Ui.alpha 0.12 ]
    ]
        |> Ui.row ([ Ui.paddingXY 0 4 ] ++ attrs)


viewInfoHeader : String -> Ui.Element context_ msg_
viewInfoHeader name =
    Ui.text name
        |> Ui.el
            [ Font.size 17
            , Ui.paddingXY 0 3
            , Ui.alpha 0.7
            ]


viewHeadline : String -> Ui.Element context_ msg_
viewHeadline name =
    name
        |> Ui.text
        |> Ui.el [ Font.size 23 ]



-- utils


toUiColor : Color -> Ui.Color
toUiColor color =
    let
        { red, green, blue, alpha } =
            color |> Color.toRgba
    in
    Ui.rgba red green blue alpha


edges : { right : number, top : number, left : number, bottom : number }
edges =
    { right = 0, top = 0, left = 0, bottom = 0 }
