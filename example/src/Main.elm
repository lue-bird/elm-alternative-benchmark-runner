module Main exposing (main)

import Array exposing (Array)
import Benchmark exposing (Benchmark, benchmark, describe, scale)
import Benchmark.Alternative exposing (rank)
import Benchmark.Runner.Alternative exposing (Program, program)


main : Program
main =
    program suite


suite : Benchmark
suite =
    describe "example"
        [ describe "array operations"
            [ rank "range from 0"
                (\f -> f 100)
                [ ( "with initialize", from0WithInitialize )
                , ( "with List.range", from0WithListRange )
                , ( "with indexedMap", from0WithIndexedMap )
                ]
            , let
                list =
                    List.repeat 100 ()
              in
              benchmark "fromList"
                (\() -> Array.fromList list)
            ]
        , describe "list operations"
            [ scale "repeat"
                (List.range 1 6
                    |> List.map ((*) 10)
                    |> List.map
                        (\n ->
                            ( n |> String.fromInt
                            , \() -> List.repeat n ()
                            )
                        )
                )
            , scale "reverse"
                (List.range 1 6
                    |> List.map ((*) 10)
                    |> List.map
                        (\n -> ( n, List.range 0 n ))
                    |> List.map
                        (\( n, listOfN ) ->
                            ( n |> String.fromInt
                            , \() -> List.reverse listOfN
                            )
                        )
                )
            ]
        ]


from0WithInitialize : Int -> Array Int
from0WithInitialize length =
    Array.initialize length identity


from0WithListRange : Int -> Array Int
from0WithListRange length =
    Array.fromList (List.range 0 (length - 1))


from0WithIndexedMap : Int -> Array Int
from0WithIndexedMap length =
    Array.repeat length ()
        |> Array.indexedMap (\i _ -> i)
