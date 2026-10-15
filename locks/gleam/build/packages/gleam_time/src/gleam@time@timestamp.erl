-module(gleam@time@timestamp).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([compare/2, system_time/0, difference/2, add/2, subtract/2, to_rfc3339/2, to_calendar/2, to_http_date/1, from_calendar/3, parse_rfc3339/1, expand_rfc850_year_relative_to/2, parse_http_date/1, from_unix_seconds/1, from_unix_seconds_and_nanoseconds/2, to_unix_seconds/1, to_unix_seconds_and_nanoseconds/1]).
-export_type([timestamp/0]).
-moduledoc(~" Welcome to the timestamp module! This module and its `Timestamp` type are
 what you will be using most commonly when working with time in Gleam.

 A timestamp represents an exact moment in time, with nanosecond precision.
 It is unambiguous as it does not need time-zone information, and it is
 fast and efficient to work with.

 Timestamps are internally represented as the duration from a fixed point
 in time, making it an _epoch_ time system. Other widely used epoch time
 systems include GPS time, Windows filetime, Unix time, NTP time, and
 PostgreSQL time.

 # Wall clock time and monotonicity

 Time is very complicated, especially on computers! While they generally do
 a good job of keeping track of what the time is, computers can get
 out-of-sync and start to report a time that is too late or too early. Most
 computers use \"network time protocol\" to tell each other what they think
 the time is, and computers that realise they are running too fast or too
 slow will adjust their clock to correct it. When this happens it can seem
 to your program that the current time has changed, and it may have even
 jumped backwards in time!

 This measure of time is called _wall clock time_, and it is what people
 commonly think of when they think of time. It is important to be aware that
 it can go backwards, and your program must not rely on it only ever going
 forwards at a steady rate. For example, for tracking what order events happen
 in. 

 This module uses wall clock time. If your program needs time values to always
 increase you will need a _monotonic_ time instead. It's uncommon that you
 would need monotonic time, one example might be if you're making a
 benchmarking framework.

 The exact way that time works will depend on what runtime you use. The
 Erlang documentation on time has a lot of detail about time generally as well
 as how it works on the BEAM, it is worth reading.
 <https://www.erlang.org/doc/apps/erts/time_correction>.

 # Converting to local calendar time

 Timestamps don't take into account time zones, so a moment in time will
 have the same timestamp value regardless of where you are in the world. To
 convert them to local time you will need to know the offset for the time
 zone you wish to use, likely from a time zone database. See the
 `gleam/time/calendar` module for more information.
").

-opaque timestamp() :: {timestamp, integer(), integer()}.

-file("src/gleam/time/timestamp.gleam", 124).
-spec normalise(timestamp()) -> timestamp().
-doc(~" Ensure the time is represented with `nanoseconds` being positive and less
 than 1 second.

 This function does not change the time that the timestamp refers to, it
 only adjusts the values used to represent the time.
").
normalise(Timestamp) ->
    Multiplier = 1000000000,
    Nanoseconds = case Multiplier of
        0 ->
            0;

        _value ->
            erlang:element(3, Timestamp) rem _value
    end,
    Overflow = erlang:element(3, Timestamp) - Nanoseconds,
    Seconds = erlang:element(2, Timestamp) + case Multiplier of
        0 ->
            0;

        _value@1 ->
            Overflow div _value@1
    end,
    case Nanoseconds >= 0 of
        true ->
            {timestamp, Seconds, Nanoseconds};

        false ->
            {timestamp, Seconds - 1, Multiplier + Nanoseconds}
    end.

-file("src/gleam/time/timestamp.gleam", 146).
-spec compare(timestamp(), timestamp()) -> gleam@order:order().
-doc(~" Compare one timestamp to another, indicating whether the first is further
 into the future (greater) or further into the past (lesser) than the
 second.

 # Examples

 ```gleam
 compare(from_unix_seconds(1), from_unix_seconds(2))
 // -> order.Lt
 ```
").
compare(Left, Right) ->
    gleam@order:break_tie(gleam@int:compare(erlang:element(2, Left), erlang:element(2, Right)), gleam@int:compare(erlang:element(3, Left), erlang:element(3, Right))).

-file("src/gleam/time/timestamp.gleam", 165).
-spec system_time() -> timestamp().
-doc(~" Get the current system time.

 Note this time is not unique or monotonic, it could change at any time or
 even go backwards! The exact behaviour will depend on the runtime used. See
 the module documentation for more information.

 On Erlang this uses [`erlang:system_time/1`][1]. On JavaScript this uses
 [`Date.now`][2].

 [1]: https://www.erlang.org/doc/apps/erts/erlang#system_time/1
 [2]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Date/now
").
system_time() ->
    {Seconds, Nanoseconds} = gleam_time_ffi:system_time(),
    normalise({timestamp, Seconds, Nanoseconds}).

-file("src/gleam/time/timestamp.gleam", 185).
-spec difference(timestamp(), timestamp()) -> gleam@time@duration:duration().
-doc(~" Calculate the difference between two timestamps.

 This is effectively substracting the first timestamp from the second.

 # Examples

 ```gleam
 difference(from_unix_seconds(1), from_unix_seconds(5))
 // -> duration.seconds(4)
 ```
").
difference(Left, Right) ->
    Seconds = gleam@time@duration:seconds(erlang:element(2, Right) - erlang:element(2, Left)),
    Nanoseconds = gleam@time@duration:nanoseconds(erlang:element(3, Right) - erlang:element(3, Left)),
    gleam@time@duration:add(Seconds, Nanoseconds).

-file("src/gleam/time/timestamp.gleam", 200).
-spec add(timestamp(), gleam@time@duration:duration()) -> timestamp().
-doc(~" Add a duration to a timestamp.

 # Examples

 ```gleam
 add(from_unix_seconds(1000), duration.seconds(5))
 // -> from_unix_seconds(1005)
 ```
").
add(Timestamp, Duration) ->
    {Seconds, Nanoseconds} = gleam@time@duration:to_seconds_and_nanoseconds(Duration),
    _pipe = {timestamp, erlang:element(2, Timestamp) + Seconds, erlang:element(3, Timestamp) + Nanoseconds},
    normalise(_pipe).

-file("src/gleam/time/timestamp.gleam", 215).
-spec subtract(timestamp(), gleam@time@duration:duration()) -> timestamp().
-doc(~" Subtract a duration from a timestamp.

 # Examples

 ```gleam
 subtract(from_unix_seconds(1000), duration.seconds(5))
 // -> from_unix_seconds(955)
 ```
 ").
subtract(Timestamp, Duration) ->
    {Seconds, Nanoseconds} = gleam@time@duration:to_seconds_and_nanoseconds(Duration),
    _pipe = {timestamp, erlang:element(2, Timestamp) - Seconds, erlang:element(3, Timestamp) - Nanoseconds},
    normalise(_pipe).

-file("src/gleam/time/timestamp.gleam", 520).
-spec do_remove_trailing_zeros(list(integer())) -> list(integer()).
do_remove_trailing_zeros(Reversed_digits) ->
    case Reversed_digits of
        [] ->
            [];

        [Digit | Digits] when Digit =:= 0 ->
            do_remove_trailing_zeros(Digits);

        Reversed_digits@1 ->
            lists:reverse(Reversed_digits@1)
    end.

-file("src/gleam/time/timestamp.gleam", 514).
-spec remove_trailing_zeros(list(integer())) -> list(integer()).
-doc(~" Given a list of digits, return new list with any trailing zeros removed.
 ").
remove_trailing_zeros(Digits) ->
    Reversed_digits = lists:reverse(Digits),
    do_remove_trailing_zeros(Reversed_digits).

-file("src/gleam/time/timestamp.gleam", 451).
-spec floored_div(integer(), float()) -> integer().
floored_div(Numerator, Denominator) ->
    N = case Denominator of
        +0.0 ->
            +0.0;

        -0.0 ->
            -0.0;

        _value ->
            erlang:float(Numerator) / _value
    end,
    erlang:round(math:floor(N)).

-file("src/gleam/time/timestamp.gleam", 535).
-spec do_get_zero_padded_digits(integer(), list(integer()), integer()) -> list(integer()).
do_get_zero_padded_digits(Number, Digits, Count) ->
    case Number of
        Number@1 when (Number@1 =< 0) andalso (Count >= 9) ->
            Digits;

        Number@2 when Number@2 =< 0 ->
            do_get_zero_padded_digits(Number@2, [0 | Digits], Count + 1);

        Number@3 ->
            Digit = Number@3 rem 10,
            Number@4 = floored_div(Number@3, 10.0),
            do_get_zero_padded_digits(Number@4, [Digit | Digits], Count + 1)
    end.

-file("src/gleam/time/timestamp.gleam", 531).
-spec get_zero_padded_digits(integer()) -> list(integer()).
-doc(~" Returns the list of digits of `number`.  If the number of digits is less 
 than 9, the result is zero-padded at the front.
 ").
get_zero_padded_digits(Number) ->
    do_get_zero_padded_digits(Number, [], 0).

-file("src/gleam/time/timestamp.gleam", 494).
-spec show_second_fraction(integer()) -> binary().
-doc(~" Converts nanoseconds into a `String` representation of fractional seconds.
 
 Assumes that `nanoseconds < 1_000_000_000`, which will be true for any 
 normalised timestamp.
 ").
show_second_fraction(Nanoseconds) ->
    case gleam@int:compare(Nanoseconds, 0) of
        lt ->
            ~"";

        eq ->
            ~"";

        gt ->
            Second_fraction_part = begin
                _pipe = Nanoseconds,
                _pipe@1 = get_zero_padded_digits(_pipe),
                _pipe@2 = remove_trailing_zeros(_pipe@1),
                _pipe@3 = gleam@list:map(_pipe@2, fun erlang:integer_to_binary/1),
                gleam@string:join(_pipe@3, ~"")
            end,
            <<"."/utf8, Second_fraction_part/binary>>
    end.

-file("src/gleam/time/timestamp.gleam", 336).
-spec pad_digit(integer(), integer()) -> binary().
pad_digit(Digit, Desired_length) ->
    _pipe = erlang:integer_to_binary(Digit),
    gleam@string:pad_start(_pipe, Desired_length, ~"0").

-file("src/gleam/time/timestamp.gleam", 444).
-spec modulo(integer(), integer()) -> integer().
modulo(N, M) ->
    case gleam@int:modulo(N, M) of
        {ok, N@1} ->
            N@1;

        {error, _} ->
            0
    end.

-file("src/gleam/time/timestamp.gleam", 457).
-spec to_civil(integer()) -> {integer(), integer(), integer()}.
to_civil(Minutes) ->
    Raw_day = floored_div(Minutes, 60.0 * 24.0) + 719468,
    Era = case Raw_day >= 0 of
        true ->
            Raw_day div 146097;

        false ->
            (Raw_day - 146096) div 146097
    end,
    Day_of_era = Raw_day - (Era * 146097),
    Year_of_era = (((Day_of_era - (Day_of_era div 1460)) + (Day_of_era div 36524)) - (Day_of_era div 146096)) div 365,
    Year = Year_of_era + (Era * 400),
    Day_of_year = Day_of_era - (((365 * Year_of_era) + (Year_of_era div 4)) - (Year_of_era div 100)),
    Mp = ((5 * Day_of_year) + 2) div 153,
    Month = case Mp < 10 of
        true ->
            Mp + 3;

        false ->
            Mp - 9
    end,
    Day = (Day_of_year - (((153 * Mp) + 2) div 5)) + 1,
    Year@1 = case Month =< 2 of
        true ->
            Year + 1;

        false ->
            Year
    end,
    {Year@1, Month, Day}.

-file("src/gleam/time/timestamp.gleam", 386).
-spec to_calendar_from_offset(timestamp(), integer()) -> {integer(), integer(), integer(), integer(), integer(), integer()}.
to_calendar_from_offset(Timestamp, Offset) ->
    Total = erlang:element(2, Timestamp) + (Offset * 60),
    Seconds = modulo(Total, 60),
    Total_minutes = floored_div(Total, 60.0),
    Minutes = modulo(Total, 60 * 60) div 60,
    Hours = case 60 * 60 of
        0 ->
            0;

        _value ->
            modulo(Total, (24 * 60) * 60) div _value
    end,
    {Year, Month, Day} = to_civil(Total_minutes),
    {Year, Month, Day, Hours, Minutes, Seconds}.

-file("src/gleam/time/timestamp.gleam", 382).
-spec duration_to_minutes(gleam@time@duration:duration()) -> integer().
duration_to_minutes(Duration) ->
    erlang:round(gleam@time@duration:to_seconds(Duration) / 60.0).

-file("src/gleam/time/timestamp.gleam", 260).
-spec to_rfc3339(timestamp(), gleam@time@duration:duration()) -> binary().
-doc(~" Convert a timestamp to a RFC 3339 formatted time string, with an offset
 supplied as an additional argument.

 The output of this function is also ISO 8601 compatible so long as the
 offset not negative. Offsets have at-most minute precision, so an offset
 with higher precision will be rounded to the nearest minute.

 If you are making an API such as a HTTP JSON API you are encouraged to use
 Unix timestamps instead of this format or ISO 8601. Unix timestamps are a
 better choice as they don't contain offset information. Consider:

 - UTC offsets are not time zones. This does not and cannot tell us the time
   zone in which the date was recorded. So what are we supposed to do with
   this information?
 - Users typically want dates formatted according to their local time zone.
   What if the provided UTC offset is different from the current user's time
   zone? What are we supposed to do with it then?
 - Despite it being useless (or worse, a source of bugs), the UTC offset
   creates a larger payload to transfer.

 They also uses more memory than a unix timestamp. The way they are better
 than Unix timestamp is that it is easier for a human to read them, but
 this is a hinderance that tooling can remedy, and APIs are not primarily
 for humans.

 # Examples

 ```gleam
 timestamp.from_unix_seconds_and_nanoseconds(1000, 123_000_000)
 |> to_rfc3339(calendar.utc_offset)
 // -> \"1970-01-01T00:16:40.123Z\"
 ```

 ```gleam
 timestamp.from_unix_seconds(1000)
 |> to_rfc3339(duration.seconds(3600))
 // -> \"1970-01-01T01:16:40+01:00\"
 ```
").
to_rfc3339(Timestamp, Offset) ->
    Offset@1 = duration_to_minutes(Offset),
    {Years, Months, Days, Hours, Minutes, Seconds} = to_calendar_from_offset(Timestamp, Offset@1),
    Offset_minutes = modulo(Offset@1, 60),
    Offset_hours = gleam@int:absolute_value(floored_div(Offset@1, 60.0)),
    N2 = fun(_capture) ->
        pad_digit(_capture, 2)
    end,
    N4 = fun(_capture) ->
        pad_digit(_capture, 4)
    end,
    Out = ~"",
    Out@1 = <<<<<<<<<<Out/binary, (N4(Years))/binary>>/binary, "-"/utf8>>/binary, (N2(Months))/binary>>/binary, "-"/utf8>>/binary, (N2(Days))/binary>>,
    Out@2 = <<Out@1/binary, "T"/utf8>>,
    Out@3 = <<<<<<<<<<Out@2/binary, (N2(Hours))/binary>>/binary, ":"/utf8>>/binary, (N2(Minutes))/binary>>/binary, ":"/utf8>>/binary, (N2(Seconds))/binary>>,
    Out@4 = <<Out@3/binary, (show_second_fraction(erlang:element(3, Timestamp)))/binary>>,
    case gleam@int:compare(Offset@1, 0) of
        eq ->
            <<Out@4/binary, "Z"/utf8>>;

        gt ->
            <<<<<<<<Out@4/binary, "+"/utf8>>/binary, (N2(Offset_hours))/binary>>/binary, ":"/utf8>>/binary, (N2(Offset_minutes))/binary>>;

        lt ->
            <<<<<<<<Out@4/binary, "-"/utf8>>/binary, (N2(Offset_hours))/binary>>/binary, ":"/utf8>>/binary, (N2(Offset_minutes))/binary>>
    end.

-file("src/gleam/time/timestamp.gleam", 332).
-spec month_to_http_string(gleam@time@calendar:month()) -> binary().
month_to_http_string(Month) ->
    gleam@string:slice(gleam@time@calendar:month_to_string(Month), 0, 3).

-file("src/gleam/time/timestamp.gleam", 319).
-spec weekday_to_http_string(integer()) -> binary().
weekday_to_http_string(Weekday) ->
    case Weekday of
        0 ->
            ~"Thu";

        1 ->
            ~"Fri";

        2 ->
            ~"Sat";

        3 ->
            ~"Sun";

        4 ->
            ~"Mon";

        5 ->
            ~"Tue";

        _ ->
            ~"Wed"
    end.

-file("src/gleam/time/timestamp.gleam", 355).
-spec to_calendar(timestamp(), gleam@time@duration:duration()) -> {gleam@time@calendar:date(), gleam@time@calendar:time_of_day()}.
-doc(~" Convert a `Timestamp` to calendar time, suitable for presenting to a human
 to read.

 If you want a machine to use the time value then you should not use this
 function and should instead keep it as a timestamp. See the documentation
 for the `gleam/time/calendar` module for more information.

 # Examples

 ```gleam
 timestamp.from_unix_seconds(0)
 |> timestamp.to_calendar(calendar.utc_offset)
 // -> #(Date(1970, January, 1), TimeOfDay(0, 0, 0, 0))
 ```
").
to_calendar(Timestamp, Offset) ->
    Offset@1 = duration_to_minutes(Offset),
    {Year, Month, Day, Hours, Minutes, Seconds} = to_calendar_from_offset(Timestamp, Offset@1),
    Month@1 = case Month of
        1 ->
            january;

        2 ->
            february;

        3 ->
            march;

        4 ->
            april;

        5 ->
            may;

        6 ->
            june;

        7 ->
            july;

        8 ->
            august;

        9 ->
            september;

        10 ->
            october;

        11 ->
            november;

        _ ->
            december
    end,
    Nanoseconds = erlang:element(3, Timestamp),
    Date = {date, Year, Month@1, Day},
    Time = {time_of_day, Hours, Minutes, Seconds, Nanoseconds},
    {Date, Time}.

-file("src/gleam/time/timestamp.gleam", 297).
-spec to_http_date(timestamp()) -> binary().
-doc(~" Convert a timestamp to an [HTTP-date formatted time string][spec].

 [spec]: https://datatracker.ietf.org/doc/html/rfc9110#section-5.6.7

 The result uses the IMF-fixdate format in GMT. HTTP dates have one-second
 precision, so nanoseconds are discarded.

 # Examples

 ```gleam
 timestamp.from_unix_seconds(0)
 |> timestamp.to_http_date
 // -> \"Thu, 01 Jan 1970 00:00:00 GMT\"
 ```
").
to_http_date(Timestamp) ->
    {Date, Time} = to_calendar(Timestamp, {duration, 0, 0}),
    Days_since_epoch = floored_div(erlang:element(2, Timestamp), erlang:float(86400)),
    Weekday = modulo(Days_since_epoch, 7),
    N2 = fun(_capture) ->
        pad_digit(_capture, 2)
    end,
    N4 = fun(_capture) ->
        pad_digit(_capture, 4)
    end,
    Out = <<(weekday_to_http_string(Weekday))/binary, ", "/utf8>>,
    Out@1 = <<<<<<<<<<Out/binary, (N2(erlang:element(4, Date)))/binary>>/binary, " "/utf8>>/binary, (month_to_http_string(erlang:element(3, Date)))/binary>>/binary, " "/utf8>>/binary, (N4(erlang:element(2, Date)))/binary>>,
    Out@2 = <<Out@1/binary, " "/utf8>>,
    Out@3 = <<<<<<<<<<Out@2/binary, (N2(erlang:element(2, Time)))/binary>>/binary, ":"/utf8>>/binary, (N2(erlang:element(3, Time)))/binary>>/binary, ":"/utf8>>/binary, (N2(erlang:element(4, Time)))/binary>>,
    <<Out@3/binary, " GMT"/utf8>>.

-file("src/gleam/time/timestamp.gleam", 1110).
-spec julian_day_from_ymd(integer(), integer(), integer()) -> integer().
-doc(~" Note: It is the callers responsibility to ensure the inputs are valid.
 
 See https://www.tondering.dk/claus/cal/julperiod.php#formula
 ").
julian_day_from_ymd(Year, Month, Day) ->
    Adjustment = (14 - Month) div 12,
    Adjusted_year = (Year + 4800) - Adjustment,
    Adjusted_month = (Month + (12 * Adjustment)) - 3,
    (((((Day + (((153 * Adjusted_month) + 2) div 5)) + (365 * Adjusted_year)) + (Adjusted_year div 4)) - (Adjusted_year div 100)) + (Adjusted_year div 400)) - 32045.

-file("src/gleam/time/timestamp.gleam", 1089).
-spec julian_seconds_from_parts(integer(), integer(), integer(), integer(), integer(), integer()) -> integer().
-doc(~" `julian_seconds_from_parts(year, month, day, hours, minutes, seconds)` 
 returns the number of Julian 
 seconds represented by the given arguments.
 
 Note: It is the callers responsibility to ensure the inputs are valid.
 
 See https://www.tondering.dk/claus/cal/julperiod.php#formula
 ").
julian_seconds_from_parts(Year, Month, Day, Hours, Minutes, Seconds) ->
    Julian_day_seconds = julian_day_from_ymd(Year, Month, Day) * 86400,
    ((Julian_day_seconds + (Hours * 3600)) + (Minutes * 60)) + Seconds.

-file("src/gleam/time/timestamp.gleam", 1059).
-spec from_date_time(integer(), integer(), integer(), integer(), integer(), integer(), integer(), integer()) -> timestamp().
-doc(~" Note: The caller of this function must ensure that all inputs are valid.
 ").
from_date_time(Year, Month, Day, Hours, Minutes, Seconds, Second_fraction_as_nanoseconds, Offset_seconds) ->
    Julian_seconds = julian_seconds_from_parts(Year, Month, Day, Hours, Minutes, Seconds),
    Julian_seconds_since_epoch = Julian_seconds - 210866803200,
    _pipe = {timestamp, Julian_seconds_since_epoch - Offset_seconds, Second_fraction_as_nanoseconds},
    normalise(_pipe).

-file("src/gleam/time/timestamp.gleam", 413).
-spec from_calendar(gleam@time@calendar:date(), gleam@time@calendar:time_of_day(), gleam@time@duration:duration()) -> timestamp().
-doc(~" Create a `Timestamp` from a human-readable calendar time.

 # Examples

 ```gleam
 timestamp.from_calendar(
   date: calendar.Date(2024, calendar.December, 25),
   time: calendar.TimeOfDay(12, 30, 50, 0),
   offset: calendar.utc_offset,
 )
 |> timestamp.to_rfc3339(calendar.utc_offset)
 // -> \"2024-12-25T12:30:50Z\"
 ```
").
from_calendar(Date, Time, Offset) ->
    Month = case erlang:element(3, Date) of
        january ->
            1;

        february ->
            2;

        march ->
            3;

        april ->
            4;

        may ->
            5;

        june ->
            6;

        july ->
            7;

        august ->
            8;

        september ->
            9;

        october ->
            10;

        november ->
            11;

        december ->
            12
    end,
    from_date_time(erlang:element(2, Date), Month, erlang:element(4, Date), erlang:element(2, Time), erlang:element(3, Time), erlang:element(4, Time), erlang:element(5, Time), erlang:round(gleam@time@duration:to_seconds(Offset))).

-file("src/gleam/time/timestamp.gleam", 1050).
-spec accept_empty(bitstring()) -> {ok, nil} | {error, nil}.
accept_empty(Bytes) ->
    case Bytes of
        <<>> ->
            {ok, nil};

        _ ->
            {error, nil}
    end.

-file("src/gleam/time/timestamp.gleam", 990).
-spec offset_to_seconds(binary(), integer(), integer()) -> integer().
offset_to_seconds(Sign, Hours, Minutes) ->
    Abs_seconds = (Hours * 3600) + (Minutes * 60),
    case Sign of
        ~"-" ->
            - Abs_seconds;

        _ ->
            Abs_seconds
    end.

-file("src/gleam/time/timestamp.gleam", 1008).
-spec do_parse_digits(bitstring(), integer(), integer(), integer()) -> {ok, {integer(), bitstring()}} | {error, nil}.
do_parse_digits(Bytes, Count, Acc, K) ->
    case Bytes of
        _ when K >= Count ->
            {ok, {Acc, Bytes}};

        <<Byte, Remaining_bytes/binary>> when (48 =< Byte) andalso (Byte =< 57) ->
            do_parse_digits(Remaining_bytes, Count, (Acc * 10) + (Byte - 48), K + 1);

        _ ->
            {error, nil}
    end.

-file("src/gleam/time/timestamp.gleam", 1001).
-spec parse_digits(bitstring(), integer()) -> {ok, {integer(), bitstring()}} | {error, nil}.
-doc(~" Parse and return the given number of digits from the given bytes.
 ").
parse_digits(Bytes, Count) ->
    do_parse_digits(Bytes, Count, 0, 0).

-file("src/gleam/time/timestamp.gleam", 890).
-spec parse_minutes(bitstring()) -> {ok, {integer(), bitstring()}} | {error, nil}.
parse_minutes(Bytes) ->
    gleam@result:'try'(parse_digits(Bytes, 2), fun(_use0) ->
        {Minutes, Bytes@1} = _use0,
        case (0 =< Minutes) andalso (Minutes =< 59) of
            true ->
                {ok, {Minutes, Bytes@1}};

            false ->
                {error, nil}
        end
    end).

-file("src/gleam/time/timestamp.gleam", 1029).
-spec accept_byte(bitstring(), integer()) -> {ok, bitstring()} | {error, nil}.
-doc(~" Accept the given value from `bytes` and move past it if found.
 ").
accept_byte(Bytes, Value) ->
    case Bytes of
        <<Byte, Remaining_bytes/binary>> when Byte =:= Value ->
            {ok, Remaining_bytes};

        _ ->
            {error, nil}
    end.

-file("src/gleam/time/timestamp.gleam", 882).
-spec parse_hours(bitstring()) -> {ok, {integer(), bitstring()}} | {error, nil}.
parse_hours(Bytes) ->
    gleam@result:'try'(parse_digits(Bytes, 2), fun(_use0) ->
        {Hours, Bytes@1} = _use0,
        case (0 =< Hours) andalso (Hours =< 23) of
            true ->
                {ok, {Hours, Bytes@1}};

            false ->
                {error, nil}
        end
    end).

-file("src/gleam/time/timestamp.gleam", 982).
-spec parse_sign(bitstring()) -> {ok, {binary(), bitstring()}} | {error, nil}.
parse_sign(Bytes) ->
    case Bytes of
        <<"+"/utf8, Remaining_bytes/binary>> ->
            {ok, {~"+", Remaining_bytes}};

        <<"-"/utf8, Remaining_bytes@1/binary>> ->
            {ok, {~"-", Remaining_bytes@1}};

        _ ->
            {error, nil}
    end.

-file("src/gleam/time/timestamp.gleam", 971).
-spec parse_numeric_offset(bitstring()) -> {ok, {integer(), bitstring()}} | {error, nil}.
parse_numeric_offset(Bytes) ->
    gleam@result:'try'(parse_sign(Bytes), fun(_use0) ->
        {Sign, Bytes@1} = _use0,
        gleam@result:'try'(parse_hours(Bytes@1), fun(_use0@1) ->
            {Hours, Bytes@2} = _use0@1,
            gleam@result:'try'(accept_byte(Bytes@2, 58), fun(Bytes@3) ->
                gleam@result:'try'(parse_minutes(Bytes@3), fun(_use0@2) ->
                    {Minutes, Bytes@4} = _use0@2,
                    Offset_seconds = offset_to_seconds(Sign, Hours, Minutes),
                    {ok, {Offset_seconds, Bytes@4}}
                end)
            end)
        end)
    end).

-file("src/gleam/time/timestamp.gleam", 963).
-spec parse_offset(bitstring()) -> {ok, {integer(), bitstring()}} | {error, nil}.
parse_offset(Bytes) ->
    case Bytes of
        <<"Z"/utf8, Remaining_bytes/binary>> ->
            {ok, {0, Remaining_bytes}};

        <<"z"/utf8, Remaining_bytes/binary>> ->
            {ok, {0, Remaining_bytes}};

        _ ->
            parse_numeric_offset(Bytes)
    end.

-file("src/gleam/time/timestamp.gleam", 929).
-spec do_parse_second_fraction_as_nanoseconds(bitstring(), integer(), integer()) -> {ok, {integer(), bitstring()}} | {error, any()}.
do_parse_second_fraction_as_nanoseconds(Bytes, Acc, Power) ->
    Power@1 = Power div 10,
    case Bytes of
        <<Byte, Remaining_bytes/binary>> when ((48 =< Byte) andalso (Byte =< 57)) andalso (Power@1 < 1) ->
            do_parse_second_fraction_as_nanoseconds(Remaining_bytes, Acc, Power@1);

        <<Byte@1, Remaining_bytes@1/binary>> when (48 =< Byte@1) andalso (Byte@1 =< 57) ->
            Digit = Byte@1 - 48,
            do_parse_second_fraction_as_nanoseconds(Remaining_bytes@1, Acc + (Digit * Power@1), Power@1);

        _ ->
            {ok, {Acc, Bytes}}
    end.

-file("src/gleam/time/timestamp.gleam", 909).
-spec parse_second_fraction_as_nanoseconds(bitstring()) -> {ok, {integer(), bitstring()}} | {error, nil}.
parse_second_fraction_as_nanoseconds(Bytes) ->
    case Bytes of
        <<"."/utf8, Byte, Remaining_bytes/binary>> when (48 =< Byte) andalso (Byte =< 57) ->
            do_parse_second_fraction_as_nanoseconds(<<Byte, Remaining_bytes/bitstring>>, 0, 1000000000);

        <<"."/utf8, _/binary>> ->
            {error, nil};

        _ ->
            {ok, {0, Bytes}}
    end.

-file("src/gleam/time/timestamp.gleam", 898).
-spec parse_seconds(bitstring()) -> {ok, {integer(), bitstring()}} | {error, nil}.
parse_seconds(Bytes) ->
    gleam@result:'try'(parse_digits(Bytes, 2), fun(_use0) ->
        {Seconds, Bytes@1} = _use0,
        case (0 =< Seconds) andalso (Seconds =< 60) of
            true ->
                {ok, {Seconds, Bytes@1}};

            false ->
                {error, nil}
        end
    end).

-file("src/gleam/time/timestamp.gleam", 1039).
-spec accept_date_time_separator(bitstring()) -> {ok, bitstring()} | {error, nil}.
accept_date_time_separator(Bytes) ->
    case Bytes of
        <<Byte, Remaining_bytes/binary>> when ((Byte =:= 84) orelse (Byte =:= 116)) orelse (Byte =:= 32) ->
            {ok, Remaining_bytes};

        _ ->
            {error, nil}
    end.

-file("src/gleam/time/timestamp.gleam", 878).
-spec is_leap_year(integer()) -> boolean().
is_leap_year(Year) ->
    ((Year rem 4) =:= 0) andalso (((Year rem 100) /= 0) orelse ((Year rem 400) =:= 0)).

-file("src/gleam/time/timestamp.gleam", 852).
-spec parse_day(bitstring(), integer(), integer()) -> {ok, {integer(), bitstring()}} | {error, nil}.
parse_day(Bytes, Year, Month) ->
    gleam@result:'try'(parse_digits(Bytes, 2), fun(_use0) ->
        {Day, Bytes@1} = _use0,
        gleam@result:'try'(case Month of
            1 ->
                {ok, 31};

            3 ->
                {ok, 31};

            5 ->
                {ok, 31};

            7 ->
                {ok, 31};

            8 ->
                {ok, 31};

            10 ->
                {ok, 31};

            12 ->
                {ok, 31};

            4 ->
                {ok, 30};

            6 ->
                {ok, 30};

            9 ->
                {ok, 30};

            11 ->
                {ok, 30};

            2 ->
                case is_leap_year(Year) of
                    true ->
                        {ok, 29};

                    false ->
                        {ok, 28}
                end;

            _ ->
                {error, nil}
        end, fun(Max_day) ->
            case (1 =< Day) andalso (Day =< Max_day) of
                true ->
                    {ok, {Day, Bytes@1}};

                false ->
                    {error, nil}
            end
        end)
    end).

-file("src/gleam/time/timestamp.gleam", 844).
-spec parse_month(bitstring()) -> {ok, {integer(), bitstring()}} | {error, nil}.
parse_month(Bytes) ->
    gleam@result:'try'(parse_digits(Bytes, 2), fun(_use0) ->
        {Month, Bytes@1} = _use0,
        case (1 =< Month) andalso (Month =< 12) of
            true ->
                {ok, {Month, Bytes@1}};

            false ->
                {error, nil}
        end
    end).

-file("src/gleam/time/timestamp.gleam", 840).
-spec parse_year(bitstring()) -> {ok, {integer(), bitstring()}} | {error, nil}.
parse_year(Bytes) ->
    parse_digits(Bytes, 4).

-file("src/gleam/time/timestamp.gleam", 607).
-spec parse_rfc3339(binary()) -> {ok, timestamp()} | {error, nil}.
-doc(~" Parses an [RFC 3339 formatted time string][spec] into a `Timestamp`.

 [spec]: https://datatracker.ietf.org/doc/html/rfc3339#section-5.6
 
 # Examples

 ```gleam
 let assert Ok(ts) = timestamp.parse_rfc3339(\"1970-01-01T00:00:01Z\")
 timestamp.to_unix_seconds_and_nanoseconds(ts)
 // -> #(1, 0)
 ```
 
 Parsing an invalid timestamp returns an error.
 
 ```gleam
 let assert Error(Nil) = timestamp.parse_rfc3339(\"1995-10-31\")
 ```

 ## Time zones

 It may at first seem that the RFC 3339 format includes timezone
 information, as it can specify an offset such as `Z` or `+3`, so why does
 this function not return calendar time with a time zone? There are multiple
 reasons:

 - RFC 3339's timestamp format is based on calendar time, but it is
   unambigous, so it can be converted into epoch time when being parsed. It
   is always better to internally use epoch time to represent unambiguous
   points in time, so we perform that conversion as a convenience and to
   ensure that programmers with less time experience don't accidentally use
   a less suitable time representation.

 - RFC 3339's contains _calendar time offset_ information, not time zone
   information. This is enough to convert it to an unambiguous timestamp,
   but it is not enough information to reliably work with calendar time.
   Without the time zone and the time zone database it's not possible to
   know what time period that offset is valid for, so it cannot be used
   without risk of bugs.

 ## Behaviour details
 
 - Follows the grammar specified in section 5.6 Internet Date/Time Format of 
   RFC 3339 <https://datatracker.ietf.org/doc/html/rfc3339#section-5.6>.
 - The `T` and `Z` characters may alternatively be lower case `t` or `z`, 
   respectively.
 - Full dates and full times must be separated by `T` or `t`. A space is also 
   permitted.
 - Leap seconds rules are not considered.  That is, any timestamp may 
   specify digts `00` - `60` for the seconds.
 - Any part of a fractional second that cannot be represented in the 
   nanosecond precision is tructated.  That is, for the time string, 
   `\"1970-01-01T00:00:00.1234567899Z\"`, the fractional second `.1234567899` 
   will be represented as `123_456_789` in the `Timestamp`.
 ").
parse_rfc3339(Input) ->
    Bytes = gleam_stdlib:identity(Input),
    gleam@result:'try'(parse_year(Bytes), fun(_use0) ->
        {Year, Bytes@1} = _use0,
        gleam@result:'try'(accept_byte(Bytes@1, 45), fun(Bytes@2) ->
            gleam@result:'try'(parse_month(Bytes@2), fun(_use0@1) ->
                {Month, Bytes@3} = _use0@1,
                gleam@result:'try'(accept_byte(Bytes@3, 45), fun(Bytes@4) ->
                    gleam@result:'try'(parse_day(Bytes@4, Year, Month), fun(_use0@2) ->
                        {Day, Bytes@5} = _use0@2,
                        gleam@result:'try'(accept_date_time_separator(Bytes@5), fun(Bytes@6) ->
                            gleam@result:'try'(parse_hours(Bytes@6), fun(_use0@3) ->
                                {Hours, Bytes@7} = _use0@3,
                                gleam@result:'try'(accept_byte(Bytes@7, 58), fun(Bytes@8) ->
                                    gleam@result:'try'(parse_minutes(Bytes@8), fun(_use0@4) ->
                                        {Minutes, Bytes@9} = _use0@4,
                                        gleam@result:'try'(accept_byte(Bytes@9, 58), fun(Bytes@10) ->
                                            gleam@result:'try'(parse_seconds(Bytes@10), fun(_use0@5) ->
                                                {Seconds, Bytes@11} = _use0@5,
                                                gleam@result:'try'(parse_second_fraction_as_nanoseconds(Bytes@11), fun(_use0@6) ->
                                                    {Second_fraction_as_nanoseconds, Bytes@12} = _use0@6,
                                                    gleam@result:'try'(parse_offset(Bytes@12), fun(_use0@7) ->
                                                        {Offset_seconds, Bytes@13} = _use0@7,
                                                        gleam@result:'try'(accept_empty(Bytes@13), fun(_use0@8) ->
                                                            nil = _use0@8,
                                                            {ok, from_date_time(Year, Month, Day, Hours, Minutes, Seconds, Second_fraction_as_nanoseconds, Offset_seconds)}
                                                        end)
                                                    end)
                                                end)
                                            end)
                                        end)
                                    end)
                                end)
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end).

-file("src/gleam/time/timestamp.gleam", 694).
-spec build_timestamp(gleam@time@calendar:date(), gleam@time@calendar:time_of_day()) -> {ok, timestamp()} | {error, nil}.
build_timestamp(Date, Time) ->
    case gleam@time@calendar:is_valid_date(Date) of
        false ->
            {error, nil};

        true ->
            {ok, from_calendar(Date, Time, {duration, 0, 0})}
    end.

-file("src/gleam/time/timestamp.gleam", 797).
-spec parse_time_without_nanoseconds(bitstring()) -> {ok, {gleam@time@calendar:time_of_day(), bitstring()}} | {error, nil}.
parse_time_without_nanoseconds(Bytes) ->
    gleam@result:'try'(parse_hours(Bytes), fun(_use0) ->
        {Hours, Bytes@1} = _use0,
        gleam@result:'try'(accept_byte(Bytes@1, 58), fun(Bytes@2) ->
            gleam@result:'try'(parse_minutes(Bytes@2), fun(_use0@1) ->
                {Minutes, Bytes@3} = _use0@1,
                gleam@result:'try'(accept_byte(Bytes@3, 58), fun(Bytes@4) ->
                    gleam@result:'try'(parse_seconds(Bytes@4), fun(_use0@2) ->
                        {Seconds, Bytes@5} = _use0@2,
                        Time = {time_of_day, Hours, Minutes, Seconds, 0},
                        {ok, {Time, Bytes@5}}
                    end)
                end)
            end)
        end)
    end).

-file("src/gleam/time/timestamp.gleam", 769).
-spec parse_asctime_day(bitstring()) -> {ok, {integer(), bitstring()}} | {error, nil}.
parse_asctime_day(Bytes) ->
    case Bytes of
        <<Byte, Bytes@1/binary>> when Byte =:= 32 ->
            parse_digits(Bytes@1, 1);

        _ ->
            parse_digits(Bytes, 2)
    end.

-file("src/gleam/time/timestamp.gleam", 777).
-spec parse_http_month(bitstring()) -> {ok, {gleam@time@calendar:month(), bitstring()}} | {error, nil}.
parse_http_month(Bytes) ->
    case Bytes of
        <<"Jan"/utf8, Bytes@1/binary>> ->
            {ok, {january, Bytes@1}};

        <<"Feb"/utf8, Bytes@2/binary>> ->
            {ok, {february, Bytes@2}};

        <<"Mar"/utf8, Bytes@3/binary>> ->
            {ok, {march, Bytes@3}};

        <<"Apr"/utf8, Bytes@4/binary>> ->
            {ok, {april, Bytes@4}};

        <<"May"/utf8, Bytes@5/binary>> ->
            {ok, {may, Bytes@5}};

        <<"Jun"/utf8, Bytes@6/binary>> ->
            {ok, {june, Bytes@6}};

        <<"Jul"/utf8, Bytes@7/binary>> ->
            {ok, {july, Bytes@7}};

        <<"Aug"/utf8, Bytes@8/binary>> ->
            {ok, {august, Bytes@8}};

        <<"Sep"/utf8, Bytes@9/binary>> ->
            {ok, {september, Bytes@9}};

        <<"Oct"/utf8, Bytes@10/binary>> ->
            {ok, {october, Bytes@10}};

        <<"Nov"/utf8, Bytes@11/binary>> ->
            {ok, {november, Bytes@11}};

        <<"Dec"/utf8, Bytes@12/binary>> ->
            {ok, {december, Bytes@12}};

        _ ->
            {error, nil}
    end.

-file("src/gleam/time/timestamp.gleam", 748).
-spec parse_asctime_date(binary()) -> {ok, timestamp()} | {error, nil}.
-doc(~" Sun Nov  6 08:49:37 1994").
parse_asctime_date(Input) ->
    Bytes = gleam_stdlib:identity(Input),
    gleam@result:'try'(parse_http_month(Bytes), fun(_use0) ->
        {Month, Bytes@1} = _use0,
        gleam@result:'try'(accept_byte(Bytes@1, 32), fun(Bytes@2) ->
            gleam@result:'try'(parse_asctime_day(Bytes@2), fun(_use0@1) ->
                {Day, Bytes@3} = _use0@1,
                gleam@result:'try'(accept_byte(Bytes@3, 32), fun(Bytes@4) ->
                    gleam@result:'try'(parse_time_without_nanoseconds(Bytes@4), fun(_use0@2) ->
                        {Time, Bytes@5} = _use0@2,
                        gleam@result:'try'(accept_byte(Bytes@5, 32), fun(Bytes@6) ->
                            gleam@result:'try'(parse_digits(Bytes@6, 4), fun(_use0@3) ->
                                {Year, Bytes@7} = _use0@3,
                                gleam@result:'try'(accept_empty(Bytes@7), fun(_use0@4) ->
                                    nil = _use0@4,
                                    build_timestamp({date, Year, Month, Day}, Time)
                                end)
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end).

-file("src/gleam/time/timestamp.gleam", 809).
-spec accept_gmt_literal(bitstring()) -> {ok, bitstring()} | {error, nil}.
accept_gmt_literal(Bytes) ->
    case Bytes of
        <<" GMT"/utf8, Bytes@1/binary>> ->
            {ok, Bytes@1};

        _ ->
            {error, nil}
    end.

-file("src/gleam/time/timestamp.gleam", 705).
-spec parse_imf_fixdate(binary()) -> {ok, timestamp()} | {error, nil}.
-doc(~" Sun, 06 Nov 1994 08:49:37 GMT").
parse_imf_fixdate(Input) ->
    Bytes = gleam_stdlib:identity(Input),
    gleam@result:'try'(parse_digits(Bytes, 2), fun(_use0) ->
        {Day, Bytes@1} = _use0,
        gleam@result:'try'(accept_byte(Bytes@1, 32), fun(Bytes@2) ->
            gleam@result:'try'(parse_http_month(Bytes@2), fun(_use0@1) ->
                {Month, Bytes@3} = _use0@1,
                gleam@result:'try'(accept_byte(Bytes@3, 32), fun(Bytes@4) ->
                    gleam@result:'try'(parse_digits(Bytes@4, 4), fun(_use0@2) ->
                        {Year, Bytes@5} = _use0@2,
                        gleam@result:'try'(accept_byte(Bytes@5, 32), fun(Bytes@6) ->
                            gleam@result:'try'(parse_time_without_nanoseconds(Bytes@6), fun(_use0@3) ->
                                {Time, Bytes@7} = _use0@3,
                                gleam@result:'try'(accept_gmt_literal(Bytes@7), fun(Bytes@8) ->
                                    gleam@result:'try'(accept_empty(Bytes@8), fun(_use0@4) ->
                                        nil = _use0@4,
                                        build_timestamp({date, Year, Month, Day}, Time)
                                    end)
                                end)
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end).

-file("src/gleam/time/timestamp.gleam", 827).
-spec expand_rfc850_year_relative_to(integer(), integer()) -> integer().
-doc(false).
expand_rfc850_year_relative_to(Year, Current_year) ->
    Century = Current_year - modulo(Current_year, 100),
    Candidate = Century + Year,
    case Candidate of
        Candidate@1 when Candidate@1 < (Current_year - 49) ->
            Candidate@1 + 100;

        Candidate@2 when Candidate@2 > (Current_year + 50) ->
            Candidate@2 - 100;

        Candidate@3 ->
            Candidate@3
    end.

-file("src/gleam/time/timestamp.gleam", 820).
-spec expand_rfc850_year(integer()) -> integer().
-doc(~" Recipients of a timestamp value in rfc850-date format, which uses a
 two-digit year, MUST interpret a timestamp that appears to be more than 50
 years in the future as representing the most recent year in the past that
 had the same last two digits.").
expand_rfc850_year(Year) ->
    {{date, Current_year, _, _}, _} = begin
        _pipe = system_time(),
        to_calendar(_pipe, {duration, 0, 0})
    end,
    expand_rfc850_year_relative_to(Year, Current_year).

-file("src/gleam/time/timestamp.gleam", 726).
-spec parse_rfc850_date(binary()) -> {ok, timestamp()} | {error, nil}.
-doc(~" Sunday, 06-Nov-94 08:49:37 GMT").
parse_rfc850_date(Input) ->
    Bytes = gleam_stdlib:identity(Input),
    gleam@result:'try'(parse_digits(Bytes, 2), fun(_use0) ->
        {Day, Bytes@1} = _use0,
        gleam@result:'try'(accept_byte(Bytes@1, 45), fun(Bytes@2) ->
            gleam@result:'try'(parse_http_month(Bytes@2), fun(_use0@1) ->
                {Month, Bytes@3} = _use0@1,
                gleam@result:'try'(accept_byte(Bytes@3, 45), fun(Bytes@4) ->
                    gleam@result:'try'(parse_digits(Bytes@4, 2), fun(_use0@2) ->
                        {Year, Bytes@5} = _use0@2,
                        gleam@result:'try'(accept_byte(Bytes@5, 32), fun(Bytes@6) ->
                            gleam@result:'try'(parse_time_without_nanoseconds(Bytes@6), fun(_use0@3) ->
                                {Time, Bytes@7} = _use0@3,
                                gleam@result:'try'(accept_gmt_literal(Bytes@7), fun(Bytes@8) ->
                                    gleam@result:'try'(accept_empty(Bytes@8), fun(_use0@4) ->
                                        nil = _use0@4,
                                        Date = {date, expand_rfc850_year(Year), Month, Day},
                                        build_timestamp(Date, Time)
                                    end)
                                end)
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end).

-file("src/gleam/time/timestamp.gleam", 669).
-spec parse_http_date(binary()) -> {ok, timestamp()} | {error, nil}.
-doc(~" Parses an [HTTP-date formatted time string][spec] into a `Timestamp`.

 [spec]: https://datatracker.ietf.org/doc/html/rfc9110#section-5.6.7

 # Examples

 ```gleam
 let assert Ok(ts) =
   timestamp.parse_http_date(\"Fri, 27 Dec 2024 14:24:27 GMT\")
 timestamp.to_unix_seconds_and_nanoseconds(ts)
 // -> #(1_735_309_467, 0)
 ```

 Along with the IMF-fixdate format, the obsolete RFC 850 and ANSI C
 `asctime` formats are accepted.

 Parsing an invalid HTTP date returns an error.

 ```gleam
 let assert Error(Nil) = timestamp.parse_http_date(\"not a date\")
 ```
").
parse_http_date(Input) ->
    case Input of
        <<"Monday, "/utf8, Input@1/binary>> ->
            parse_rfc850_date(Input@1);

        <<"Tuesday, "/utf8, Input@1/binary>> ->
            parse_rfc850_date(Input@1);

        <<"Wednesday, "/utf8, Input@1/binary>> ->
            parse_rfc850_date(Input@1);

        <<"Thursday, "/utf8, Input@1/binary>> ->
            parse_rfc850_date(Input@1);

        <<"Friday, "/utf8, Input@1/binary>> ->
            parse_rfc850_date(Input@1);

        <<"Saturday, "/utf8, Input@1/binary>> ->
            parse_rfc850_date(Input@1);

        <<"Sunday, "/utf8, Input@1/binary>> ->
            parse_rfc850_date(Input@1);

        <<"Mon"/utf8, Input@2/binary>> ->
            case Input@2 of
                <<", "/utf8, Input@3/binary>> ->
                    parse_imf_fixdate(Input@3);

                <<" "/utf8, Input@4/binary>> ->
                    parse_asctime_date(Input@4);

                _ ->
                    {error, nil}
            end;

        <<"Tue"/utf8, Input@2/binary>> ->
            case Input@2 of
                <<", "/utf8, Input@3/binary>> ->
                    parse_imf_fixdate(Input@3);

                <<" "/utf8, Input@4/binary>> ->
                    parse_asctime_date(Input@4);

                _ ->
                    {error, nil}
            end;

        <<"Wed"/utf8, Input@2/binary>> ->
            case Input@2 of
                <<", "/utf8, Input@3/binary>> ->
                    parse_imf_fixdate(Input@3);

                <<" "/utf8, Input@4/binary>> ->
                    parse_asctime_date(Input@4);

                _ ->
                    {error, nil}
            end;

        <<"Thu"/utf8, Input@2/binary>> ->
            case Input@2 of
                <<", "/utf8, Input@3/binary>> ->
                    parse_imf_fixdate(Input@3);

                <<" "/utf8, Input@4/binary>> ->
                    parse_asctime_date(Input@4);

                _ ->
                    {error, nil}
            end;

        <<"Fri"/utf8, Input@2/binary>> ->
            case Input@2 of
                <<", "/utf8, Input@3/binary>> ->
                    parse_imf_fixdate(Input@3);

                <<" "/utf8, Input@4/binary>> ->
                    parse_asctime_date(Input@4);

                _ ->
                    {error, nil}
            end;

        <<"Sat"/utf8, Input@2/binary>> ->
            case Input@2 of
                <<", "/utf8, Input@3/binary>> ->
                    parse_imf_fixdate(Input@3);

                <<" "/utf8, Input@4/binary>> ->
                    parse_asctime_date(Input@4);

                _ ->
                    {error, nil}
            end;

        <<"Sun"/utf8, Input@2/binary>> ->
            case Input@2 of
                <<", "/utf8, Input@3/binary>> ->
                    parse_imf_fixdate(Input@3);

                <<" "/utf8, Input@4/binary>> ->
                    parse_asctime_date(Input@4);

                _ ->
                    {error, nil}
            end;

        _ ->
            {error, nil}
    end.

-file("src/gleam/time/timestamp.gleam", 1129).
-spec from_unix_seconds(integer()) -> timestamp().
-doc(~" Create a timestamp from a number of seconds since 00:00:00 UTC on 1 January
 1970.
").
from_unix_seconds(Seconds) ->
    {timestamp, Seconds, 0}.

-file("src/gleam/time/timestamp.gleam", 1144).
-spec from_unix_seconds_and_nanoseconds(integer(), integer()) -> timestamp().
-doc(~" Create a timestamp from a number of seconds and nanoseconds since 00:00:00
 UTC on 1 January 1970.

 # JavaScript int limitations

 Remember that JavaScript can only perfectly represent ints between positive
 and negative 9,007,199,254,740,991! If you only use the nanosecond field
 then you will almost certainly not get the date value you want due to this
 loss of precision. Always use seconds primarily and then use nanoseconds
 for the final sub-second adjustment.
").
from_unix_seconds_and_nanoseconds(Seconds, Nanoseconds) ->
    _pipe = {timestamp, Seconds, Nanoseconds},
    normalise(_pipe).

-file("src/gleam/time/timestamp.gleam", 1158).
-spec to_unix_seconds(timestamp()) -> float().
-doc(~" Convert the timestamp to a number of seconds since 00:00:00 UTC on 1
 January 1970.

 There may be some small loss of precision due to `Timestamp` being
 nanosecond accurate and `Float` not being able to represent this.
").
to_unix_seconds(Timestamp) ->
    Seconds = erlang:float(erlang:element(2, Timestamp)),
    Nanoseconds = erlang:float(erlang:element(3, Timestamp)),
    Seconds + (Nanoseconds / 1000000000.0).

-file("src/gleam/time/timestamp.gleam", 1167).
-spec to_unix_seconds_and_nanoseconds(timestamp()) -> {integer(), integer()}.
-doc(~" Convert the timestamp to a number of seconds and nanoseconds since 00:00:00
 UTC on 1 January 1970. There is no loss of precision with this conversion
 on any target.").
to_unix_seconds_and_nanoseconds(Timestamp) ->
    {erlang:element(2, Timestamp), erlang:element(3, Timestamp)}.

