-module(gleam@time@duration).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([approximate/1, compare/2, difference/2, add/2, subtract/2, to_iso8601_string/1, seconds/1, minutes/1, hours/1, milliseconds/1, nanoseconds/1, to_seconds/1, to_seconds_and_nanoseconds/1, to_milliseconds/1]).
-export_type([duration/0, unit/0]).

-opaque duration() :: {duration, integer(), integer()}.

-type unit() :: nanosecond | microsecond | millisecond | second | minute | hour | day | week | month | year.

-file("src/gleam/time/duration.gleam", 110).
-spec normalise(duration()) -> duration().
-doc(~" Ensure the duration is represented with `nanoseconds` being positive and
 less than 1 second.

 This function does not change the amount of time that the duration refers
 to, it only adjusts the values used to represent the time.
").
normalise(Duration) ->
    Multiplier = 1000000000,
    Nanoseconds = case Multiplier of
        0 ->
            0;

        _value ->
            erlang:element(3, Duration) rem _value
    end,
    Overflow = erlang:element(3, Duration) - Nanoseconds,
    Seconds = erlang:element(2, Duration) + case Multiplier of
        0 ->
            0;

        _value@1 ->
            Overflow div _value@1
    end,
    case Nanoseconds >= 0 of
        true ->
            {duration, Seconds, Nanoseconds};

        false ->
            {duration, Seconds - 1, Multiplier + Nanoseconds}
    end.

-file("src/gleam/time/duration.gleam", 76).
-spec approximate(duration()) -> {integer(), unit()}.
-doc(~" Convert a duration to a number of the largest number of a unit, serving as
 a rough description of the duration that a human can understand.

 The size used for each unit are described in the documentation for the
 `Unit` type.

 ```gleam
 seconds(125)
 |> approximate
 // -> #(2, Minute)
 ```

 This function rounds _towards zero_. This means that if a duration is just
 short of 2 days then it will approximate to 1 day.

 ```gleam
 hours(47)
 |> approximate
 // -> #(1, Day)
 ```
").
approximate(Duration) ->
    {duration, S, Ns} = Duration,
    Minute = 60,
    Hour = Minute * 60,
    Day = Hour * 24,
    Week = Day * 7,
    Year = (Day * 365) + (Hour * 6),
    Month = Year div 12,
    Microsecond = 1000,
    Millisecond = Microsecond * 1000,
    case nil of
        _ when S < 0 ->
            {Amount, Unit} = begin
                _pipe = {duration, - S, - Ns},
                _pipe@1 = normalise(_pipe),
                approximate(_pipe@1)
            end,
            {- Amount, Unit};

        _ when S >= Year ->
            {case Year of
                0 ->
                    0;

                _value ->
                    S div _value
            end, year};

        _ when S >= Month ->
            {case Month of
                0 ->
                    0;

                _value@1 ->
                    S div _value@1
            end, month};

        _ when S >= Week ->
            {case Week of
                0 ->
                    0;

                _value@2 ->
                    S div _value@2
            end, week};

        _ when S >= Day ->
            {case Day of
                0 ->
                    0;

                _value@3 ->
                    S div _value@3
            end, day};

        _ when S >= Hour ->
            {case Hour of
                0 ->
                    0;

                _value@4 ->
                    S div _value@4
            end, hour};

        _ when S >= Minute ->
            {case Minute of
                0 ->
                    0;

                _value@5 ->
                    S div _value@5
            end, minute};

        _ when S > 0 ->
            {S, second};

        _ when Ns >= Millisecond ->
            {case Millisecond of
                0 ->
                    0;

                _value@6 ->
                    Ns div _value@6
            end, millisecond};

        _ when Ns >= Microsecond ->
            {case Microsecond of
                0 ->
                    0;

                _value@7 ->
                    Ns div _value@7
            end, microsecond};

        _ ->
            {Ns, nanosecond}
    end.

-file("src/gleam/time/duration.gleam", 140).
-spec compare(duration(), duration()) -> gleam@order:order().
-doc(~" Compare one duration to another, indicating whether the first spans a
 larger amount of time (and so is greater) or smaller amount of time (and so
 is lesser) than the second.

 # Examples

 ```gleam
 compare(seconds(1), seconds(2))
 // -> order.Lt
 ```

 Whether a duration is negative or positive doesn't matter for comparing
 them, only the amount of time spanned matters.

 ```gleam
 compare(seconds(-2), seconds(1))
 // -> order.Gt
 ```
").
compare(Left, Right) ->
    Parts = fun(X) ->
        case erlang:element(2, X) >= 0 of
            true ->
                {erlang:element(2, X), erlang:element(3, X)};

            false ->
                {(erlang:element(2, X) * -1) - 1, 1000000000 - erlang:element(3, X)}
        end
    end,
    {Ls, Lns} = Parts(Left),
    {Rs, Rns} = Parts(Right),
    _pipe = gleam@int:compare(Ls, Rs),
    gleam@order:break_tie(_pipe, gleam@int:compare(Lns, Rns)).

-file("src/gleam/time/duration.gleam", 164).
-spec difference(duration(), duration()) -> duration().
-doc(~" Calculate the difference between two durations.

 This is effectively subtracting the first duration from the second.

 # Examples

 ```gleam
 difference(seconds(1), seconds(5))
 // -> seconds(4)
 ```
").
difference(Left, Right) ->
    _pipe = {duration, erlang:element(2, Right) - erlang:element(2, Left), erlang:element(3, Right) - erlang:element(3, Left)},
    normalise(_pipe).

-file("src/gleam/time/duration.gleam", 178).
-spec add(duration(), duration()) -> duration().
-doc(~" Add two durations together.

 # Examples

 ```gleam
 add(seconds(1), seconds(5))
 // -> seconds(6)
 ```
").
add(Left, Right) ->
    _pipe = {duration, erlang:element(2, Left) + erlang:element(2, Right), erlang:element(3, Left) + erlang:element(3, Right)},
    normalise(_pipe).

-file("src/gleam/time/duration.gleam", 192).
-spec subtract(duration(), duration()) -> duration().
-doc(~" Subtract one durations from another.

 # Examples

 ```gleam
 subtract(seconds(5), seconds(1))
 // -> seconds(4)
 ```
").
subtract(Left, Right) ->
    _pipe = {duration, erlang:element(2, Left) - erlang:element(2, Right), erlang:element(3, Left) - erlang:element(3, Right)},
    normalise(_pipe).

-file("src/gleam/time/duration.gleam", 239).
-spec nanosecond_digits(integer(), integer(), binary()) -> binary().
nanosecond_digits(N, Position, Acc) ->
    case Position of
        9 ->
            Acc;

        _ when (Acc =:= ~"") andalso ((N rem 10) =:= 0) ->
            nanosecond_digits(N div 10, Position + 1, Acc);

        _ ->
            Acc@1 = <<(erlang:integer_to_binary(N rem 10))/binary, Acc/binary>>,
            nanosecond_digits(N div 10, Position + 1, Acc@1)
    end.

-file("src/gleam/time/duration.gleam", 206).
-spec to_iso8601_string(duration()) -> binary().
-doc(~" Convert the duration to an [ISO8601][1] formatted duration string.

 The ISO8601 duration format is ambiguous without context due to months and
 years having different lengths, and because of leap seconds. This function
 encodes the duration as days, hours, and seconds without any leap seconds.
 Be sure to take this into account when using the duration strings.

 [1]: https://en.wikipedia.org/wiki/ISO_8601#Durations
").
to_iso8601_string(Duration) ->
    gleam@bool:guard(Duration =:= {duration, 0, 0}, ~"PT0S", fun() ->
        Split = fun(Total, Limit) ->
            Amount = case Limit of
                0 ->
                    0;

                _value ->
                    Total rem _value
            end,
            Remainder = case Limit of
                0 ->
                    0;

                _value@1 ->
                    (Total - Amount) div _value@1
            end,
            {Amount, Remainder}
        end,
        {Seconds, Rest} = Split(erlang:element(2, Duration), 60),
        {Minutes, Rest@1} = Split(Rest, 60),
        {Hours, Rest@2} = Split(Rest@1, 24),
        Days = Rest@2,
        Add = fun(Out, Value, Unit) ->
            case Value of
                0 ->
                    Out;

                _ ->
                    <<<<Out/binary, (erlang:integer_to_binary(Value))/binary>>/binary, Unit/binary>>
            end
        end,
        Output = begin
            _pipe = ~"P",
            _pipe@1 = Add(_pipe, Days, ~"D"),
            _pipe@2 = gleam@string:append(_pipe@1, ~"T"),
            _pipe@3 = Add(_pipe@2, Hours, ~"H"),
            Add(_pipe@3, Minutes, ~"M")
        end,
        case {Seconds, erlang:element(3, Duration)} of
            {0, 0} ->
                Output;

            {_, 0} ->
                <<<<Output/binary, (erlang:integer_to_binary(Seconds))/binary>>/binary, "S"/utf8>>;

            {_, _} ->
                F = nanosecond_digits(erlang:element(3, Duration), 0, ~""),
                <<<<<<<<Output/binary, (erlang:integer_to_binary(Seconds))/binary>>/binary, "."/utf8>>/binary, F/binary>>/binary, "S"/utf8>>
        end
    end).

-file("src/gleam/time/duration.gleam", 253).
-spec seconds(integer()) -> duration().
-doc(~" Create a duration of a number of seconds.").
seconds(Amount) ->
    {duration, Amount, 0}.

-file("src/gleam/time/duration.gleam", 258).
-spec minutes(integer()) -> duration().
-doc(~" Create a duration of a number of minutes.").
minutes(Amount) ->
    seconds(Amount * 60).

-file("src/gleam/time/duration.gleam", 263).
-spec hours(integer()) -> duration().
-doc(~" Create a duration of a number of hours.").
hours(Amount) ->
    seconds((Amount * 60) * 60).

-file("src/gleam/time/duration.gleam", 268).
-spec milliseconds(integer()) -> duration().
-doc(~" Create a duration of a number of milliseconds.").
milliseconds(Amount) ->
    Remainder = Amount rem 1000,
    Overflow = Amount - Remainder,
    Nanoseconds = Remainder * 1000000,
    Seconds = Overflow div 1000,
    _pipe = {duration, Seconds, Nanoseconds},
    normalise(_pipe).

-file("src/gleam/time/duration.gleam", 287).
-spec nanoseconds(integer()) -> duration().
-doc(~" Create a duration of a number of nanoseconds.

 # JavaScript int limitations

 Remember that JavaScript can only perfectly represent ints between positive
 and negative 9,007,199,254,740,991! If you use a single call to this
 function to create durations larger than that number of nanoseconds then
 you will likely not get exactly the value you expect. Use `seconds` and
 `milliseconds` as much as possible for large durations.
").
nanoseconds(Amount) ->
    _pipe = {duration, 0, Amount},
    normalise(_pipe).

-file("src/gleam/time/duration.gleam", 297).
-spec to_seconds(duration()) -> float().
-doc(~" Convert the duration to a number of seconds.

 There may be some small loss of precision due to `Duration` being
 nanosecond accurate and `Float` not being able to represent this.
").
to_seconds(Duration) ->
    Seconds = erlang:float(erlang:element(2, Duration)),
    Nanoseconds = erlang:float(erlang:element(3, Duration)),
    Seconds + (Nanoseconds / 1000000000.0).

-file("src/gleam/time/duration.gleam", 306).
-spec to_seconds_and_nanoseconds(duration()) -> {integer(), integer()}.
-doc(~" Convert the duration to a number of seconds and nanoseconds. There is no
 loss of precision with this conversion on any target.
").
to_seconds_and_nanoseconds(Duration) ->
    {erlang:element(2, Duration), erlang:element(3, Duration)}.

-file("src/gleam/time/duration.gleam", 315).
-spec to_milliseconds(duration()) -> integer().
-doc(~" Convert the duration to a number of milliseconds.

 This conversion truncates any sub-millisecond precision. If you need
 the full precision, use `to_seconds_and_nanoseconds` instead.
").
to_milliseconds(Duration) ->
    Seconds_ms = erlang:element(2, Duration) * 1000,
    Nanos_ms = erlang:element(3, Duration) div 1000000,
    Seconds_ms + Nanos_ms.

